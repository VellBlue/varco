/* Varco helper: runs in the bottle alongside Steam.
 * When a game window appears, it minimizes Steam's main window. */
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
    for (;;) {
        Sleep(1500);
        if (!steam_running()) { if (++idle > 40) break; continue; }   /* quits ~1 minute after Steam closes */
        idle = 0;
        game_found = FALSE; EnumWindows(find_game, 0);
        if (game_found && !was_playing) { Sleep(1500); EnumWindows(minimize_steam, 0); }
        was_playing = game_found;
    }
    CloseHandle(m); return 0;
}
