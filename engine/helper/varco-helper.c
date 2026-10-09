/* Varco helper: runs in the bottle alongside Steam.
 * When a game window appears, it minimizes Steam's main window. It also confirms the "graphics driver too old"
 * warnings that games show at startup (D3DMetal reports a GPU with a driver version they don't know): the game
 * waits for OK and then runs normally. Only message boxes of games that talk about the driver and offer nothing
 * but OK are confirmed: the helper never answers a question for the user. Game windows as large as the screen but
 * moved away from it are put back in place. */
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <tlhelp32.h>
#include <wchar.h>

static const WCHAR *ignored[] = { L"steam.exe", L"steamwebhelper.exe", L"steamservice.exe", L"explorer.exe",
    L"services.exe", L"winedevice.exe", L"plugplay.exe", L"svchost.exe", L"rpcss.exe", L"conhost.exe",
    L"rundll32.exe", L"varco-helper.exe", L"redprelauncher.exe", L"redlauncher.exe", L"qtwebengineprocess.exe",
    L"crashreporter.exe", L"unitycrashhandler64.exe", L"gldriverquery64.exe", L"vulkandriverquery64.exe" };

static BOOL exe_name(DWORD pid, WCHAR *out, DWORD len)
{
    HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    WCHAR path[MAX_PATH]; DWORD n = MAX_PATH; BOOL ok = FALSE;
    if (!h) return FALSE;
    if (QueryFullProcessImageNameW(h, 0, path, &n)) {
        WCHAR *b = wcsrchr(path, L'\\'); lstrcpynW(out, b ? b + 1 : path, len); CharLowerW(out); ok = TRUE;
    }
    CloseHandle(h); return ok;
}

static BOOL is_ignored(const WCHAR *name)
{
    for (unsigned i = 0; i < sizeof(ignored) / sizeof(ignored[0]); i++) if (!wcscmp(name, ignored[i])) return TRUE;
    return FALSE;
}

static BOOL steam_running(void)
{
    HANDLE s = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0); PROCESSENTRY32W pe = { sizeof pe }; BOOL found = FALSE;
    for (BOOL ok = Process32FirstW(s, &pe); ok && !found; ok = Process32NextW(s, &pe))
        if (!_wcsicmp(pe.szExeFile, L"steam.exe")) found = TRUE;
    CloseHandle(s); return found;
}

static BOOL game_found;
static BOOL CALLBACK find_game(HWND h, LPARAM l)
{
    RECT r; DWORD pid; WCHAR name[128];
    if (!IsWindowVisible(h) || IsIconic(h) || GetWindow(h, GW_OWNER)) return TRUE;
    GetWindowRect(h, &r);
    if (r.right - r.left < 800 || r.bottom - r.top < 500) return TRUE;
    GetWindowThreadProcessId(h, &pid);
    if (!exe_name(pid, name, 128) || is_ignored(name)) return TRUE;
    game_found = TRUE; return FALSE;
}

/* "driver" in the languages games use for these warnings (compared in lowercase) */
static const WCHAR *driver_words[] = { L"driver", L"treiber", L"pilote", L"controlador", L"sterownik",
    L"\x0434\x0440\x0430\x0439\x0432\x0435\x0440" /* драйвер */, L"\x30c9\x30e9\x30a4\x30d0" /* ドライバ */,
    L"\x9a71\x52a8" /* 驱动 */, L"\x9a45\x52d5" /* 驅動 */, L"\xb4dc\xb77c\xc774\xbc84" /* 드라이버 */ };

static BOOL CALLBACK confirm_warning(HWND h, LPARAM l)
{
    DWORD pid; WCHAR name[128], cls[16], text[2048];
    if (!IsWindowVisible(h)) return TRUE;
    GetClassNameW(h, cls, 16);
    if (wcscmp(cls, L"#32770")) return TRUE;   /* standard message box */
    GetWindowThreadProcessId(h, &pid);
    if (!exe_name(pid, name, 128) || is_ignored(name)) return TRUE;
    if (!wcscmp(name, L"rdr2.exe") && GetDlgItem(h, IDOK))   /* its warning, known: confirmed as it is */
    {
        PostMessageW(h, WM_COMMAND, MAKEWPARAM(IDOK, BN_CLICKED), (LPARAM)GetDlgItem(h, IDOK));
        return TRUE;
    }
    if (!GetDlgItem(h, IDOK) || GetDlgItem(h, IDCANCEL) || GetDlgItem(h, IDNO)) return TRUE;   /* only plain warnings */
    if (!GetDlgItemTextW(h, 0xffff, text, 2048)) return TRUE;   /* the message box's text */
    CharLowerW(text);
    for (unsigned i = 0; i < sizeof(driver_words) / sizeof(driver_words[0]); i++)
        if (wcsstr(text, driver_words[i]))
        {
            PostMessageW(h, WM_COMMAND, MAKEWPARAM(IDOK, BN_CLICKED), (LPARAM)GetDlgItem(h, IDOK));
            break;
        }
    return TRUE;
}

/* a game window exactly as large as its screen but moved away from it goes back to the screen's corner: with an
 * emulated lower resolution (Boost), some games center their window using the desktop size they read at startup */
static BOOL CALLBACK snap_fullscreen(HWND h, LPARAM l)
{
    RECT r; MONITORINFO mi = { sizeof(mi) }; DWORD pid; WCHAR name[128];
    if (!IsWindowVisible(h) || IsIconic(h) || GetWindow(h, GW_OWNER)) return TRUE;
    if (!GetWindowRect(h, &r) || !GetMonitorInfoW(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST), &mi)) return TRUE;
    if (r.right - r.left != mi.rcMonitor.right - mi.rcMonitor.left || r.bottom - r.top != mi.rcMonitor.bottom - mi.rcMonitor.top) return TRUE;
    if (r.left == mi.rcMonitor.left && r.top == mi.rcMonitor.top) return TRUE;
    GetWindowThreadProcessId(h, &pid);
    if (!exe_name(pid, name, 128) || is_ignored(name)) return TRUE;
    SetWindowPos(h, NULL, mi.rcMonitor.left, mi.rcMonitor.top, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    return TRUE;
}

static BOOL CALLBACK minimize_steam(HWND h, LPARAM l)
{
    DWORD pid; WCHAR name[128], cls[64];
    if (!IsWindowVisible(h) || IsIconic(h)) return TRUE;
    GetClassNameW(h, cls, 64);
    GetWindowThreadProcessId(h, &pid);
    if (exe_name(pid, name, 128) && !wcscmp(name, L"steamwebhelper.exe") && !wcscmp(cls, L"SDL_app"))
        ShowWindow(h, SW_MINIMIZE);
    return TRUE;
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, LPWSTR cmd, int show)
{
    HANDLE m = CreateMutexW(NULL, TRUE, L"VarcoSteamHelper");
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;
    BOOL was_playing = FALSE; int idle = 0;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);   /* real window and screen sizes */
    for (;;) {
        Sleep(1500);
        if (!steam_running()) { if (++idle > 40) break; continue; }   /* quits ~1 minute after Steam closes */
        idle = 0;
        EnumWindows(confirm_warning, 0);
        EnumWindows(snap_fullscreen, 0);
        game_found = FALSE; EnumWindows(find_game, 0);
        if (game_found && !was_playing) { Sleep(1500); EnumWindows(minimize_steam, 0); }
        was_playing = game_found;
    }
    CloseHandle(m); return 0;
}
