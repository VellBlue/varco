import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

let home = FileManager.default.homeDirectoryForCurrentUser
/// Data folder (engines, bottles, logs): ~/Varco if it exists, otherwise ~/Library/Application Support/Varco.
/// It can be changed with the "rootPath" preference.
let rootURL: URL = {
    if let custom = UserDefaults.standard.string(forKey: "rootPath"), !custom.isEmpty { return URL(fileURLWithPath: custom) }
    let visible = home.appendingPathComponent("Varco")
    if FileManager.default.fileExists(atPath: visible.appendingPathComponent("engines").path) { return visible }
    return home.appendingPathComponent("Library/Application Support/Varco")
}()
let bottlesURL = rootURL.appendingPathComponent("bottles")
/// The varco command ships inside the app (Contents/Resources/cli); during development the one in the data folder is used
let cliPath: String = Bundle.main.path(forResource: "varco", ofType: nil, inDirectory: "cli")
    ?? rootURL.appendingPathComponent("varco").path

/// Packages published in the GitHub Releases. With a new engine, update URL, SHA-256 (printed by
/// engine/package-*.sh) and size: scripts/build-app.sh warns if they don't match the packages in ../varco-release.
enum VarcoRelease {
    /// App version (scripts/build-app.sh copies it into Info.plist; Release tags are "v" + version)
    static let appVersion = "1.0"
    static let repo = URL(string: "https://github.com/VellBlue/varco")!
    static let latestAPI = URL(string: "https://api.github.com/repos/VellBlue/varco/releases/latest")!
    static let newIssue = URL(string: "https://github.com/VellBlue/varco/issues/new/choose")!
    static let engineVersion = "26.3-1"
    static let engineURL = URL(string: "https://github.com/VellBlue/varco/releases/download/v1.0/varco-engine-26.3-1.tar.xz")!
    static let engineSHA256 = "946e7bcbc9b12ab56be118a80d0a9d407f21232c4fbd5a74d5cc314cbaf34a07"
    static let engineSize = "129 MB"
    static let d3dmetalURL = URL(string: "https://github.com/VellBlue/varco/releases/download/v1.0/varco-d3dmetal-gptk3.0.tar.xz")!
    static let d3dmetalSHA256 = "d36e9c7671c2bac980a0e532e52df1cfd125a8327fddc008b07609121d6cb1ef"
    static let gptkPage = URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!
}

/// Stores and launchers installed from the app ("varco install-store"; the same paths are in cli/varco)
struct Launcher: Identifiable {
    let id: String, name: String, exe: [String], symbol: String
    /// Stores without a launcher to install: the page to download the game installers from opens
    var page: URL? = nil
    static let all = [
        Launcher(id: "epic", name: "Epic Games", exe: [#"C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"#, #"C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"#], symbol: "e.square.fill"),
        // GOG Galaxy 2.1 doesn't render in Varco (see cli/varco): GOG games, DRM-free, install from the offline installers
        Launcher(id: "gog", name: "GOG", exe: [], symbol: "g.square.fill", page: URL(string: "https://www.gog.com/account")!),
        // the EA app installs into a folder named after its version number
        Launcher(id: "ea", name: "EA app", exe: [#"C:\Program Files\Electronic Arts\EA Desktop\*\EA Desktop\EADesktop.exe"#], symbol: "a.square.fill"),
        Launcher(id: "ubisoft", name: "Ubisoft Connect", exe: [#"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe"#, #"C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher\upc.exe"#], symbol: "u.square.fill"),
        Launcher(id: "battlenet", name: "Battle.net", exe: [#"C:\Program Files (x86)\Battle.net\Battle.net Launcher.exe"#, #"C:\Program Files (x86)\Battle.net\Battle.net.exe"#], symbol: "b.square.fill"),
    ]
}

/// Games that only read Xbox controllers: the DualSense shows up as an Xbox pad unless chosen otherwise (as in varco-tool)
let xinputByDefault: Set<String> = ["1174180"]   // Red Dead Redemption 2

/// Varco's color (burgundy; brighter in dark mode), same as the icon and video
extension Color {
    static let varco = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.816, green: 0.345, blue: 0.478, alpha: 1)
            : NSColor(srgbRed: 0.478, green: 0.067, blue: 0.192, alpha: 1) })
}

/// The arch of the Varco logo (the "varco", the gateway games pass through)
struct ArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath(); return p
    }
}
struct ArchIcon: View {
    var size: CGFloat = 32
    var body: some View {
        ArchShape()
            .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.78, blue: 0.82), Color(red: 0.77, green: 0.28, blue: 0.43), Color(red: 0.36, green: 0.05, blue: 0.16)],
                                 startPoint: .bottom, endPoint: .top))
            .overlay(ArchShape().stroke(Color.primary.opacity(0.85), lineWidth: size * 0.07))
            .frame(width: size * 0.64, height: size)
    }
}

/// Italian or English text: follows the Mac's language, or the choice made in the app ("language": auto/it/en).
func L(_ it: String, _ en: String) -> String {
    let pref = UserDefaults.standard.string(forKey: "language") ?? "auto"
    let italian = pref == "it" || (pref == "auto" && (Locale.preferredLanguages.first ?? "en").hasPrefix("it"))
    return italian ? it : en
}

/// DirectX version a game uses, worked out from its files.
enum DirectX: String, Codable {
    case dx12Only, dx11And12, dx11OrOlder, unknown

    var badge: String? {
        switch self {
        case .dx12Only: "DX12"
        case .dx11And12: "DX11 · DX12"
        case .dx11OrOlder: "DX11"
        case .unknown: nil
        }
    }
    var color: Color {
        switch self {
        case .dx12Only: .orange
        case .dx11And12: .blue
        default: .green
        }
    }
}

/// Display name: titles Steam writes in ALL CAPS become "Title Case"
/// (Roman numerals and acronyms stay as they are); titles that already have lowercase letters are left alone.
func displayName(_ raw: String) -> String {
    let letters = raw.filter { $0.isLetter }
    guard !letters.isEmpty, !letters.contains(where: { $0.isLowercase }) else { return raw }
    let keep: Set<String> = ["II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII", "XIII", "XIV", "XV", "XVI",
                             "HD", "VR", "GOTY", "RPG", "DLC", "ATP", "WTA", "USA", "UK", "2D", "3D", "FPS", "DX", "DX11", "DX12", "GTA", "NBA", "NFL", "FIFA", "UFC", "WWE", "F1"]
    let small: Set<String> = ["of", "the", "and", "a", "an", "in", "on", "at", "to", "for", "or", "vs", "di", "del", "della", "e"]
    return raw.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { i, w -> String in
        let word = String(w), core = word.trimmingCharacters(in: .punctuationCharacters)
        if keep.contains(core) { return word }
        let lower = word.lowercased()
        if i > 0 && small.contains(core.lowercased()) { return lower }
        guard let f = lower.firstIndex(where: { $0.isLetter }) else { return lower }
        return lower.replacingCharacters(in: f...f, with: lower[f].uppercased())
    }.joined(separator: " ")
}

struct Game: Identifiable, Hashable {
    let id: String
    let name: String
    let installed: Bool
    let art: URL?
    let folder: URL?
    let size: String
    /// Download progress (0...1) while Steam downloads or updates the game
    var progress: Double? = nil
    /// Active FPS limit (0 = no limit), read from Varco's preferences or from the game's settings
    var fps: Int? = nil
}

struct Program: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

struct BottleSettings: Equatable {
    var engine = "cx26"
    var hud = false
    var msync = true
    var retina = false
    var dxr = false
    var metalfx = false
    var cmdctrl = false
    var optalt = false
    /// Windows interface size in DPI (96 = 100%, 192 = 200%); 0 = not set (Windows uses 96)
    var dpi = 0
}

struct Bottle: Identifiable, Hashable {
    let name: String
    var id: String { "varco:\(name)" }
    var url: URL { bottlesURL.appendingPathComponent(name) }
    var steamURL: URL { url.appendingPathComponent("drive_c/Program Files (x86)/Steam") }
    var hasSteam: Bool { FileManager.default.fileExists(atPath: steamURL.appendingPathComponent("steam.exe").path) }

    func settings() -> BottleSettings {
        var s = BottleSettings()
        guard let text = try? String(contentsOf: url.appendingPathComponent("varco.conf"), encoding: .utf8) else { return s }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "ENGINE": s.engine = parts[1]
            case "HUD": s.hud = parts[1] == "1"
            case "MSYNC": s.msync = parts[1] == "1"
            case "RETINA": s.retina = parts[1] == "1"
            case "DXR": s.dxr = parts[1] == "1"
            case "METALFX": s.metalfx = parts[1] == "1"
            case "CMDCTRL": s.cmdctrl = parts[1] == "1"
            case "OPTALT": s.optalt = parts[1] == "1"
            case "DPI": s.dpi = Int(parts[1]) ?? 0
            default: break
            }
        }
        return s
    }

    /// DirectX version chosen for a game with "varco dxmode" ("dx11", "dx12" or nil).
    func dxPreference(for appid: String) -> String? {
        guard let text = try? String(contentsOf: url.appendingPathComponent("varco-games.conf"), encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == appid { return parts[1] }
        }
        return nil
    }

    /// Converts a Windows path (C:\\...) into the real path on the Mac.
    func macURL(forWindowsPath win: String) -> URL? {
        let clean = win.replacingOccurrences(of: "\\\\", with: "\\")
        guard clean.count >= 2, clean[clean.index(after: clean.startIndex)] == ":" else { return nil }
        let drive = clean.prefix(1).lowercased()
        let rest = clean.dropFirst(2).split(separator: "\\").joined(separator: "/")
        let base = url.appendingPathComponent("dosdevices/\(drive):").resolvingSymlinksInPath()
        return rest.isEmpty ? base : base.appendingPathComponent(rest)
    }

    /// All Steam libraries (on other drives or folders too).
    func steamLibraries() -> [URL] {
        var libs = [steamURL]
        let vdf = steamURL.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            for line in text.split(separator: "\n") where line.contains("\"path\"") {
                let parts = line.components(separatedBy: "\"").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if let win = parts.last, let u = macURL(forWindowsPath: win),
                   !libs.contains(where: { $0.standardizedFileURL.path == u.standardizedFileURL.path }) {
                    libs.append(u)
                }
            }
        }
        return libs.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("steamapps").path) }
    }

    /// Per-game preferences (varco-games.conf): "<appid>=dx11|dx12", "<appid>.fps=N", "default.fps=N"
    func gamePrefs() -> [String: String] {
        guard let text = try? String(contentsOf: url.appendingPathComponent("varco-games.conf"), encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        for line in text.split(separator: "\n") { let kv = line.split(separator: "=", maxSplits: 1).map(String.init); if kv.count == 2 { d[kv[0]] = kv[1] } }
        return d
    }

    /// A game's FPS limit: The Witcher 3 and Death Stranding from their own settings, the others from Varco
    func fpsLimit(for game: Game, prefs: [String: String]) -> Int {
        func first(_ file: URL, _ pattern: String) -> Int? {
            guard let t = try? String(contentsOf: file, encoding: .utf8),
                  let r = t.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(t[r].filter(\.isNumber))
        }
        if game.id == "292030" {
            let users = (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("drive_c/users").path)) ?? []
            for u in users {
                let dir = url.appendingPathComponent("drive_c/users/\(u)/Documents/The Witcher 3")
                let file = dir.appendingPathComponent(prefs["292030"] == "dx12" ? "dx12user.settings" : "user.settings")
                if let v = first(file, "LimitFPS=[0-9]+") { return v }
            }
        }
        if game.id == "1850570", let f = game.folder, let v = first(f.appendingPathComponent("settings.cfg"), "\"limit_fps\"[ \t]+\"[0-9]+") { return v }
        return Int(prefs["\(game.id).fps"] ?? prefs["default.fps"] ?? "0") ?? 0
    }

    func games() -> [Game] {
        var seen = Set<String>()
        let prefs = gamePrefs()
        return steamLibraries().flatMap { games(in: $0) }.filter { seen.insert($0.id).inserted }
            .map { g in var g = g; if g.installed { g.fps = fpsLimit(for: g, prefs: prefs) }; return g }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Stores installed in this bottle
    func installedLaunchers() -> Set<String> {
        Set(Launcher.all.filter { l in l.exe.contains(where: windowsPathExists) }.map(\.id))
    }

    /// Does the C:\... file exist? A "*" component matches any folder.
    private func windowsPathExists(_ path: String) -> Bool {
        guard let star = path.range(of: #"\*\"#) else {
            return macURL(forWindowsPath: path).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
        let dir = String(path[..<star.lowerBound]), rest = String(path[star.upperBound...])
        guard let d = macURL(forWindowsPath: dir), let subs = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { return false }
        return subs.contains { windowsPathExists(dir + "\\" + $0 + "\\" + rest) }
    }

    /// Non-Steam programs: shortcuts from the Windows Start menu and desktop.
    func programs() -> [Program] {
        let fm = FileManager.default
        let drive = url.appendingPathComponent("drive_c")
        var roots = [drive.appendingPathComponent("ProgramData/Microsoft/Windows/Start Menu/Programs"),
                     drive.appendingPathComponent("users/Public/Desktop")]
        for user in (try? fm.contentsOfDirectory(atPath: drive.appendingPathComponent("users").path)) ?? [] where user != "Public" {
            let u = drive.appendingPathComponent("users/\(user)")
            roots.append(u.appendingPathComponent("AppData/Roaming/Microsoft/Windows/Start Menu/Programs"))
            roots.append(u.appendingPathComponent("Desktop"))
        }
        let skip = ["uninstall", "disinstall", "support", "help", "guida", "readme", "leggimi", "website", "manual", "steam"]
        var seen = Set<String>(), out: [Program] = []
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let f as URL in e where ["lnk", "url"].contains(f.pathExtension.lowercased()) {
                let name = f.deletingPathExtension().lastPathComponent
                let lower = name.lowercased()
                if skip.contains(where: { lower.contains($0) }) { continue }
                // .url files that open a website aren't programs, and Steam's ones are already in the library
                // (Epic games use com.epicgames.launcher:// instead)
                if f.pathExtension.lowercased() == "url",
                   let t = try? String(contentsOf: f, encoding: .utf8),
                   t.range(of: "URL=http", options: .caseInsensitive) != nil || t.range(of: "URL=steam:", options: .caseInsensitive) != nil { continue }
                if seen.insert(lower).inserted { out.append(Program(name: name, path: f.path)) }
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func games(in library: URL) -> [Game] {
        let apps = library.appendingPathComponent("steamapps")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: apps.path)) ?? []
        let hidden: Set<String> = ["228980"]   // Steamworks Common Redistributables
        return files.filter { $0.hasPrefix("appmanifest_") }.compactMap { file in
            guard let text = try? String(contentsOf: apps.appendingPathComponent(file), encoding: .utf8) else { return nil }
            func value(_ key: String) -> String? {
                guard let r = text.range(of: "\"\(key)\"\\s+\"([^\"]*)\"", options: .regularExpression) else { return nil }
                return String(text[r]).components(separatedBy: "\"").dropLast().last
            }
            guard let id = value("appid"), let name = value("name"), !hidden.contains(id) else { return nil }
            let flags = Int(value("StateFlags") ?? "0") ?? 0
            let folder = value("installdir").map { apps.appendingPathComponent("common/\($0)") }
            return Game(id: id, name: displayName(name), installed: flags & 4 != 0, art: artwork(for: id),
                        folder: folder, size: value("SizeOnDisk") ?? "0",
                        progress: { let tot = Double(value("BytesToDownload") ?? "") ?? 0, done = Double(value("BytesDownloaded") ?? "") ?? 0
                                    return flags & 4 == 0 && tot > 0 ? min(1, done / tot) : nil }())
        }
    }

    private func artwork(for id: String) -> URL? {
        let dir = steamURL.appendingPathComponent("appcache/librarycache/\(id)")
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        // Steam uses two cache formats: subfolders with library_capsule/library_header (old)
        // or files at the top of the folder with library_600x900/header (recently installed games)
        var capsule: URL?, header: URL?
        for case let f as URL in e {
            switch f.lastPathComponent {
            case "library_capsule.jpg", "library_600x900.jpg": if capsule == nil { capsule = f }
            case "library_header.jpg", "header.jpg": if header == nil { header = f }
            default: break
            }
        }
        return capsule ?? header
    }
}

// MARK: - DirectX detection

enum DirectXDetector {
    private static let ignored = ["crash", "redist", "vcredist", "directx", "dotnet", "installer", "setup",
                                  "uninst", "helper", "cef", "overlay", "anticheat", "easyanticheat", "battleye",
                                  "benchmark", "dxsetup", "ue4prereq", "ueprereq"]

    /// Scans the game's executables and libraries and looks for references to d3d11.dll / d3d12.dll.
    static func detect(folder: URL) -> DirectX {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                    options: [.skipsHiddenFiles]) else { return .unknown }
        let d3d11 = [Data("d3d11.dll".utf8), Data("D3D11.dll".utf8), Data("D3D11.DLL".utf8)]
        let d3d12 = [Data("d3d12.dll".utf8), Data("D3D12.dll".utf8), Data("D3D12.DLL".utf8)]
        var uses11 = false, uses12 = false, agility = false, scanned = 0

        for case let f as URL in e {
            if e.level > 7 { e.skipDescendants(); continue }
            let lower = f.lastPathComponent.lowercased()
            if ignored.contains(where: { lower.contains($0) }) {
                if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != true { e.skipDescendants() }
                continue
            }
            if lower == "d3d12core.dll" { agility = true; continue }
            guard lower.hasSuffix(".exe") || lower.hasSuffix(".dll") else { continue }
            // The bundled system DLLs (e.g. d3dcompiler, dxgi) say nothing about the game
            if lower.hasPrefix("d3d") || lower.hasPrefix("dxgi") || lower.hasPrefix("dxil") || lower.hasPrefix("dxcompiler") { continue }
            let size = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size < 700_000_000, scanned < 400 else { continue }
            guard let data = try? Data(contentsOf: f, options: .alwaysMapped) else { continue }
            scanned += 1
            if !uses11, d3d11.contains(where: { data.range(of: $0) != nil }) { uses11 = true }
            if !uses12, d3d12.contains(where: { data.range(of: $0) != nil }) { uses12 = true }
        }
        if agility { uses12 = true }
        switch (uses11, uses12) {
        case (true, true): return .dx11And12
        case (false, true): return .dx12Only
        case (true, false): return .dx11OrOlder
        default: return scanned > 0 ? .dx11OrOlder : .unknown
        }
    }
}

// MARK: - App state

@MainActor
final class Store: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var selection: String?
    @Published var busy: String?
    @Published var message: String?
    @Published var directX: [String: DirectX] = [:]
    /// Steam running and folders of the games being played (updated every 3 seconds)
    @Published var steamRunning = false
    @Published var runningDirs: Set<String> = []
    private var detecting = Set<String>()
    private let cacheURL = rootURL.appendingPathComponent("directx-cache.json")
    private var poller: Timer?

    /// Latest version published on GitHub, if newer than this one
    @Published var update: (version: String, page: URL)?

    init() {
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: DirectX].self, from: data) { directX = saved }
        reload()
        Task { await checkForUpdates() }
        poller = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in await self?.pollProcesses() } }
        Task { await pollProcesses() }
    }

    func pollProcesses() async {
        let (steam, dirs) = await Task.detached { () -> (Bool, Set<String>) in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-ax", "-o", "command="]
            let pipe = Pipe(); p.standardOutput = pipe
            guard (try? p.run()) != nil else { return (false, []) }
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.lowercased() ?? ""
            p.waitUntilExit()
            var dirs = Set<String>(), steam = false
            for line in text.split(separator: "\n") {
                if line.contains("\\steam\\steam.exe") { steam = true }
                if let r = line.range(of: "\\steamapps\\common\\") {
                    let rest = line[r.upperBound...]
                    if let end = rest.firstIndex(of: "\\") { dirs.insert(String(rest[..<end])) }
                }
            }
            return (steam, dirs)
        }.value
        if steam != steamRunning { steamRunning = steam }
        if dirs != runningDirs { runningDirs = dirs }
    }

    /// The engine needs Rosetta (Wine and D3DMetal are Intel programs): true if it is installed
    static func rosettaInstalled() async -> Bool {
        await Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/arch"); p.arguments = ["-x86_64", "/usr/bin/true"]
            p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit(); return p.terminationStatus == 0
        }.value
    }

    /// Checks the GitHub Releases at most once a day (can be turned off in Settings)
    func checkForUpdates() async {
        let d = UserDefaults.standard
        guard d.object(forKey: "checkUpdates") as? Bool ?? true else { update = nil; return }
        if (d.object(forKey: "lastUpdateCheck") as? Date).map({ Date().timeIntervalSince($0) > 86_400 }) ?? true {
            var req = URLRequest(url: VarcoRelease.latestAPI, timeoutInterval: 10)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String, let page = json["html_url"] as? String {
                d.set(Date(), forKey: "lastUpdateCheck"); d.set(tag, forKey: "latestTag"); d.set(page, forKey: "latestPage")
            }
        }
        if let tag = d.string(forKey: "latestTag"), let page = d.string(forKey: "latestPage").flatMap(URL.init(string:)),
           Self.isNewer(tag, than: VarcoRelease.appVersion) {
            update = (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page)
        } else { update = nil }
    }

    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { (v.hasPrefix("v") ? String(v.dropFirst()) : v).split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 } }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) { let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0; if x != y { return x > y } }
        return false
    }

    /// Moves a bottle to the Trash (it can be recovered from there), after closing its programs
    func trash(_ b: Bottle) async {
        _ = await run(["kill", b.name], status: L("Chiusura di \(b.name)…", "Closing \(b.name)…"))
        try? await Task.sleep(for: .seconds(1))
        do {
            try FileManager.default.trashItem(at: b.url, resultingItemURL: nil)
            message = L("\(b.name) è nel Cestino", "\(b.name) moved to the Trash")
        } catch {
            message = L("Non è stato possibile spostare \(b.name) nel Cestino", "Couldn't move \(b.name) to the Trash")
        }
        reload()
    }

    /// Details for a GitHub report (without the Mac's user name)
    func diagnostics(for b: Bottle) async -> String {
        func sysctl(_ name: String) -> String {
            var size = 0; sysctlbyname(name, nil, &size, nil, 0)
            var buf = [CChar](repeating: 0, count: max(size, 1)); sysctlbyname(name, &buf, &size, nil, 0)
            return String(cString: buf)
        }
        let doctor = await run(["doctor"]), show = await run(["show", b.name])
        let logURL = rootURL.appendingPathComponent("logs/\(b.name).log")
        var log = ""
        if let h = try? FileHandle(forReadingFrom: logURL) {
            let end = (try? h.seekToEnd()) ?? 0; try? h.seek(toOffset: end > 200_000 ? end - 200_000 : 0)
            log = String(decoding: h.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").filter { !$0.contains("fixme:") }.suffix(80).joined(separator: "\n")
            try? h.close()
        }
        let games = b.games().filter(\.installed).map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        let text = """
        **Varco** \(VarcoRelease.appVersion) · \(ProcessInfo.processInfo.operatingSystemVersionString) · \(sysctl("machdep.cpu.brand_string")) · \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB
        ```
        \(doctor.trimmingCharacters(in: .whitespacesAndNewlines))
        \(show.trimmingCharacters(in: .whitespacesAndNewlines))
        Games: \(games.isEmpty ? "-" : games)
        ```
        <details><summary>Log</summary>

        ```
        \(log)
        ```
        </details>
        """
        return text.replacingOccurrences(of: home.path, with: "~")
    }

    var varcoBottles: [Bottle] { bottles }

    func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: bottlesURL.path)) ?? []
        bottles = names.filter { FileManager.default.fileExists(atPath: bottlesURL.appendingPathComponent("\($0)/drive_c").path) }
            .sorted().map { Bottle(name: $0) }
        if selection == nil || !bottles.contains(where: { $0.id == selection }) { selection = bottles.first?.id }
    }

    var current: Bottle? { bottles.first { $0.id == selection } }

    // DirectX detection in the background, cached on disk
    private func key(_ game: Game) -> String { "\(game.id)-\(game.size)" }

    func directX(for game: Game) -> DirectX {
        if let known = directX[key(game)] { return known }
        guard game.installed, let folder = game.folder else { return .unknown }
        let k = key(game)
        if detecting.insert(k).inserted {
            Task {
                let result = await Task.detached(priority: .utility) { DirectXDetector.detect(folder: folder) }.value
                directX[k] = result
                detecting.remove(k)
                if let data = try? JSONEncoder().encode(directX) { try? data.write(to: cacheURL) }
            }
        }
        return .unknown
    }

    @discardableResult
    func run(_ args: [String], status: String? = nil) async -> String {
        if let status { busy = status }
        defer { if status != nil { busy = nil } }
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [cliPath] + args
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["VARCO_HOME"] = rootURL.path
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do { try p.run() } catch { return L("Errore: ", "Error: ") + error.localizedDescription }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }

    func launch(_ args: [String], note: String) {
        Task {
            await run(args)
            message = note
            try? await Task.sleep(for: .seconds(4))
            if message == note { message = nil }
        }
    }

    func openSteam(_ b: Bottle, _ extra: [String] = []) {
        launch(["steam", b.name] + extra, note: L("Steam in avvio…", "Launching Steam…"))
    }

    func play(_ game: Game, in b: Bottle, args: [String]) {
        launch(["game", b.name, game.id] + args, note: L("\(game.name) in avvio…", "Launching \(game.name)…"))
    }

    func runProgram(_ path: String, in b: Bottle, name: String) {
        launch(["run", b.name, path], note: L("\(name) in avvio…", "Launching \(name)…"))
    }

    /// Saves several settings with a single call (no concurrent writes to the same file).
    func set(_ pairs: [(String, String)], in bottle: Bottle) {
        guard !pairs.isEmpty else { return }
        Task { await run(["set", bottle.name] + pairs.flatMap { [$0.0, $0.1] }) }
    }
}

extension Notification.Name {
    static let varcoReload = Notification.Name("VarcoReload")
    static let varcoShowSetup = Notification.Name("VarcoShowSetup")
}

// MARK: - Setup assistant

/// Dependency status, read with "varco doctor"
struct SetupStatus: Equatable {
    var rosetta = false, engine = false, d3dmetal = false, steamBottles = 0
    var engineVersion = ""
    var ready: Bool { rosetta && engine && d3dmetal }
    /// The installed engine isn't the one of this Varco version: an update is offered (not blocking)
    var engineOutdated: Bool { engine && engineVersion != VarcoRelease.engineVersion }
    static func check() async -> SetupStatus {
        let out = await Task.detached { () -> String in
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/zsh"); p.arguments = [cliPath, "doctor"]
            var env = ProcessInfo.processInfo.environment; env["VARCO_HOME"] = rootURL.path; p.environment = env
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return "" }
            let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(data: d, encoding: .utf8) ?? ""
        }.value
        var s = SetupStatus()
        for line in out.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init); guard kv.count == 2 else { continue }
            switch kv[0] {
            case "rosetta": s.rosetta = kv[1] == "1"
            case "engine": s.engine = kv[1] == "1"
            case "engine_version": s.engineVersion = kv[1]
            case "d3dmetal": s.d3dmetal = kv[1] == "1"
            case "steam_bottles": s.steamBottles = Int(kv[1]) ?? 0
            default: break
            }
        }
        return s
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var status: SetupStatus?
    @State private var forceSetup = false
    @State private var askEngineUpdate = false
    var body: some View {
        Group {
            if let st = status, st.ready && !forceSetup { ContentView() }
            else if status != nil { SetupView(status: $status, done: { forceSetup = false; store.reload() }) }
            else { ProgressView(L("Controllo di Varco…", "Checking Varco…")).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .tint(.varco)
        .task {
            status = await SetupStatus.check()
            if let st = status, st.ready, st.engineOutdated { askEngineUpdate = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .varcoShowSetup)) { _ in forceSetup = true; Task { status = await SetupStatus.check() } }
        .alert(L("Aggiornamento del motore", "Engine update"), isPresented: $askEngineUpdate) {
            Button(L("Aggiorna ora", "Update now")) { forceSetup = true }
            Button(L("Più tardi", "Later"), role: .cancel) {}
        } message: {
            Text(L("È disponibile una versione aggiornata del motore di Varco (\(VarcoRelease.engineVersion)). Ci vuole un minuto; D3DMetal e i tuoi ambienti restano come sono.",
                   "An updated Varco engine is available (\(VarcoRelease.engineVersion)). It takes a minute; D3DMetal and your bottles stay as they are."))
        }
    }
}

/// Downloads the engine with progress
final class EngineDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0
    private var continuation: CheckedContinuation<URL, Error>?
    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            continuation = c
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
        if t > 0 { DispatchQueue.main.async { self.progress = Double(w) / Double(t) } }
    }
    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("varco-engine-\(UUID().uuidString).tar.xz")
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: dest); continuation?.resume(returning: dest)
        } catch { continuation?.resume(throwing: error) }
        continuation = nil
    }
    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation?.resume(throwing: error); continuation = nil }
    }
}

struct SetupView: View {
    @EnvironmentObject var store: Store
    @Binding var status: SetupStatus?
    let done: () -> Void
    @StateObject private var downloader = EngineDownloader()
    /// The step that is working, with what it is doing
    @State private var busy: StepNote?
    /// The last error, shown under its step
    @State private var failure: StepNote?
    @State private var foundDMG: URL?

    struct StepNote: Equatable { let step: Int; let text: String }

    private var st: SetupStatus { status ?? SetupStatus() }
    /// The step to do now: it has the main button
    private var current: Int {
        if !st.rosetta { return 1 }
        if !st.engine || st.engineOutdated { return 2 }
        if !st.d3dmetal { return 3 }
        return st.steamBottles == 0 ? 4 : 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 18) {
                    ArchIcon(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Benvenuto in Varco", "Welcome to Varco")).font(.largeTitle.bold())
                        Text(L("Prepariamo il Mac per i giochi Windows. Ci vogliono pochi minuti, si fa una volta sola.",
                               "Let's get your Mac ready for Windows games. It takes a few minutes, only once."))
                            .foregroundStyle(.secondary)
                    }
                }
                step(1, L("Rosetta di Apple", "Apple Rosetta"),
                     L("Permette al Mac di usare programmi per Intel: il motore di Varco ne ha bisogno.", "Lets your Mac run Intel programs: Varco's engine needs it."),
                     ok: st.rosetta) {
                    Button(L("Installa Rosetta", "Install Rosetta")) { installRosetta() }.modifier(Prominent(on: current == 1))
                }
                step(2, L("Motore Varco", "Varco engine"),
                     st.engineOutdated
                        ? L("C'è una versione aggiornata del motore (\(VarcoRelease.engineVersion), \(VarcoRelease.engineSize)). D3DMetal e i tuoi ambienti restano come sono.",
                            "An updated engine is available (\(VarcoRelease.engineVersion), \(VarcoRelease.engineSize)). D3DMetal and your bottles stay as they are.")
                        : L("Fa girare i programmi Windows sul Mac (\(VarcoRelease.engineSize)).", "Runs Windows programs on your Mac (\(VarcoRelease.engineSize))."),
                     ok: st.engine && !st.engineOutdated) {
                    HStack {
                        Button(st.engineOutdated ? L("Aggiorna il motore", "Update the engine") : L("Scarica e installa", "Download and install")) { installEngine(from: nil) }
                            .modifier(Prominent(on: current == 2))
                        if !st.engineOutdated { Button(L("Ho già il pacchetto…", "I have the package…")) { pickEngine() } }
                    }
                }
                step(3, L("D3DMetal di Apple", "Apple D3DMetal"),
                     L("Fa girare i giochi DirectX 11 e 12 con la grafica Metal del Mac.", "Runs DirectX 11 and 12 games on your Mac's Metal graphics."),
                     note: L("È un componente di Apple (Game Porting Toolkit), distribuito senza modifiche con la sua licenza, che ne consente l'uso solo per scopi non commerciali. Puoi usare anche il .dmg del Game Porting Toolkit preso dal sito Apple.",
                             "It's an Apple component (Game Porting Toolkit), distributed unmodified with Apple's license, which allows non-commercial use only. You can also use the Game Porting Toolkit .dmg from Apple's site."),
                     ok: st.d3dmetal, enabled: st.engine) {
                    HStack {
                        if let dmg = foundDMG {
                            Button(L("Usa \(dmg.lastPathComponent)", "Use \(dmg.lastPathComponent)")) { importD3DMetal(dmg) }.modifier(Prominent(on: current == 3))
                        } else {
                            Button(L("Scarica e installa (15 MB)", "Download and install (15 MB)")) { downloadD3DMetal() }.modifier(Prominent(on: current == 3))
                        }
                        Button(L("Uso il .dmg di Apple…", "Use Apple's .dmg…")) { pickDMG() }
                        Button(L("Sito Apple", "Apple's site")) { NSWorkspace.shared.open(VarcoRelease.gptkPage) }
                            .buttonStyle(.plain).foregroundStyle(Color.varco).padding(.leading, 6)
                    }
                }
                step(4, "Steam",
                     L("Crea un ambiente Windows e installa Steam dall'installer ufficiale di Valve.", "Creates a Windows bottle and installs Steam from Valve's official installer.")
                        + (st.steamBottles > 0 ? "" : L(" Si può fare anche dopo.", " You can also do it later.")),
                     ok: st.steamBottles > 0, enabled: st.ready) {
                    Button(L("Crea e installa Steam", "Create and install Steam")) { createSteamBottle() }.modifier(Prominent(on: current == 4))
                }
                HStack {
                    Spacer()
                    Button(L("Inizia", "Get started")) { done() }
                        .modifier(Prominent(on: current == 0)).controlSize(.large)
                        .disabled(!st.ready || busy != nil)
                }
            }
            .padding(36)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { findDMG() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in recheck(); findDMG() }
    }

    private struct Prominent: ViewModifier {
        let on: Bool
        @ViewBuilder func body(content: Content) -> some View {
            if on { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }

    @ViewBuilder
    private func step<Content: View>(_ n: Int, _ title: String, _ text: String, note: String? = nil, ok: Bool, enabled: Bool = true,
                                     @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(ok ? Color.green : Color.varco.opacity(enabled ? 1 : 0.35)).frame(width: 30, height: 30)
                if ok { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let note, !ok { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let b = busy, b.step == n {
                    if n == 2 {
                        ProgressView(value: downloader.progress) { Text(b.text).foregroundStyle(.secondary) }.frame(width: 300).padding(.top, 2)
                    } else {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(b.text).foregroundStyle(.secondary) }.padding(.top, 2)
                    }
                } else if !ok && enabled {
                    action().padding(.top, 2).disabled(busy != nil)
                }
                if let f = failure, f.step == n {
                    Label(f.text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(enabled || ok ? 1 : 0.55)
    }

    private func recheck() { Task { status = await SetupStatus.check() } }

    private func start(_ n: Int, _ text: String) { failure = nil; busy = StepNote(step: n, text: text) }
    private func finish(_ n: Int, error: String?) {
        busy = nil; failure = error.map { StepNote(step: n, text: $0) }; recheck()
    }

    private func installRosetta() {
        start(1, L("Installazione di Rosetta…", "Installing Rosetta…"))
        Task.detached {
            let ok: Bool = {
                var err: NSDictionary?
                NSAppleScript(source: "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges")?.executeAndReturnError(&err)
                return err == nil
            }()
            await MainActor.run { finish(1, error: ok ? nil : L("Rosetta non è stata installata.", "Rosetta was not installed.")) }
        }
    }

    private func pickEngine() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "xz")].compactMap { $0 }
        panel.directoryURL = home.appendingPathComponent("Downloads")
        if panel.runModal() == .OK, let url = panel.url { installEngine(from: url) }
    }

    private func installEngine(from local: URL?) {
        downloader.progress = local == nil ? 0 : 1
        start(2, local == nil ? L("Download…", "Downloading…") : L("Installazione…", "Installing…"))
        Task {
            var err: String?
            do {
                let file = try await (local != nil ? local! : downloader.download(VarcoRelease.engineURL))
                downloader.progress = 1; busy = StepNote(step: 2, text: L("Installazione…", "Installing…"))
                let sum = local == nil ? [VarcoRelease.engineSHA256] : []
                let out = await store.run(["setup-engine", file.path] + sum)
                if local == nil { try? FileManager.default.removeItem(at: file) }
                if out.contains("in use") { err = L("Chiudi Steam e i giochi, poi riprova.", "Quit Steam and your games, then try again.") }
                else if !out.contains("Engine installed") { err = L("Installazione del motore non riuscita: ", "Engine installation failed: ") + String(out.suffix(160)) }
            } catch {
                err = L("Download non riuscito: ", "Download failed: ") + error.localizedDescription
            }
            finish(2, error: err)
        }
    }

    /// The Game Porting Toolkit .dmg just downloaded to Downloads, if there is one
    private func findDMG() {
        let dl = home.appendingPathComponent("Downloads")
        let files = (try? FileManager.default.contentsOfDirectory(at: dl, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        foundDMG = files.filter { $0.pathExtension.lowercased() == "dmg" &&
            ($0.lastPathComponent.localizedCaseInsensitiveContains("Game Porting") || $0.lastPathComponent.localizedCaseInsensitiveContains("Evaluation environment")) }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >
                      ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }.first
    }

    private func pickDMG() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "dmg")].compactMap { $0 }
        panel.directoryURL = home.appendingPathComponent("Downloads")
        if panel.runModal() == .OK, let url = panel.url { importD3DMetal(url) }
    }

    private func downloadD3DMetal() {
        start(3, L("Download di D3DMetal…", "Downloading D3DMetal…"))
        Task {
            var err: String?
            do {
                let file = try await EngineDownloader().download(VarcoRelease.d3dmetalURL)
                let renamed = file.deletingLastPathComponent().appendingPathComponent("varco-d3dmetal.tar.xz")
                try? FileManager.default.removeItem(at: renamed); try FileManager.default.moveItem(at: file, to: renamed)
                busy = StepNote(step: 3, text: L("Installazione…", "Installing…"))
                let out = await store.run(["import-d3dmetal", renamed.path, VarcoRelease.d3dmetalSHA256])
                try? FileManager.default.removeItem(at: renamed)
                if !out.contains("D3DMetal installed") { err = String(out.suffix(200)) }
            } catch { err = L("Download non riuscito: ", "Download failed: ") + error.localizedDescription }
            finish(3, error: err)
        }
    }

    private func importD3DMetal(_ dmg: URL) {
        start(3, L("Copia di D3DMetal…", "Copying D3DMetal…"))
        Task {
            let out = await store.run(["import-d3dmetal", dmg.path])
            finish(3, error: out.contains("D3DMetal installed") ? nil : String(out.suffix(200)))
        }
    }

    private func createSteamBottle() {
        start(4, L("Creazione dell'ambiente Windows, circa un minuto…", "Creating the Windows bottle, about a minute…"))
        Task {
            let name = store.varcoBottles.contains { $0.name == "Steam" } ? "Steam 2" : "Steam"
            let created = await store.run(["create", name, "cx26"])
            guard created.contains("Done:") else {
                store.reload()
                finish(4, error: L("Creazione dell'ambiente Windows non riuscita.", "Couldn't create the Windows bottle.")); return
            }
            busy = StepNote(step: 4, text: L("Download di Steam…", "Downloading Steam…"))
            let out = await store.run(["install-steam", name])
            store.reload()
            finish(4, error: out.contains("started") ? nil : L("Installazione di Steam non riuscita.", "Steam installation failed."))
        }
    }
}

// MARK: - Interface

@main
struct VarcoApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup("Varco") {
            RootView().environmentObject(store).frame(minWidth: 880, minHeight: 580)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button(L("Installazione guidata…", "Setup assistant…")) { NotificationCenter.default.post(name: .varcoShowSetup, object: nil) }
            }
        }
        .windowToolbarStyle(.unified)
        Settings { LanguageSettings().environmentObject(store).tint(.varco) }
    }
}

struct LanguagePicker: View {
    @AppStorage("language") private var lang = "auto"
    var body: some View {
        Picker(L("Lingua", "Language"), selection: $lang) {
            Text(L("Automatica (lingua del Mac)", "Automatic (Mac language)")).tag("auto")
            Text("Italiano").tag("it")
            Text("English").tag("en")
        }
    }
}

struct LanguageSettings: View {
    @EnvironmentObject var store: Store
    @AppStorage("language") private var lang = "auto"
    @AppStorage("checkUpdates") private var checkUpdates = true
    var body: some View {
        Form {
            LanguagePicker()
            Toggle(L("Cerca aggiornamenti su GitHub (una volta al giorno)", "Check GitHub for updates (once a day)"), isOn: $checkUpdates)
                .onChange(of: checkUpdates) { _, _ in Task { await store.checkForUpdates() } }
            LabeledContent(L("Versione", "Version"), value: "\(VarcoRelease.appVersion) · " + L("motore", "engine") + " \(VarcoRelease.engineVersion)")
        }
        .formStyle(.grouped).frame(width: 420).id(lang)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var showNew = false
    @State private var toTrash: Bottle?
    @AppStorage("language") private var lang = "auto"

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section(L("Ambienti Windows", "Bottles")) {
                    ForEach(store.varcoBottles) { b in
                        Label(b.name, systemImage: b.hasSteam ? "gamecontroller.fill" : "shippingbox.fill").tag(b.id)
                            .contextMenu {
                                Button(L("Mostra nel Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([b.url]) }
                                Divider()
                                Button(L("Sposta nel Cestino…", "Move to Trash…"), role: .destructive) { toTrash = b }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                if let u = store.update {
                    Button { NSWorkspace.shared.open(u.page) } label: {
                        Label(L("Varco \(u.version) è disponibile", "Varco \(u.version) is available"), systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).padding(10)
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { showNew = true } label: { Label(L("Nuovo ambiente", "New bottle"), systemImage: "plus") }
                    .help(L("Crea un nuovo ambiente Windows", "Create a new bottle"))
                }
            }
        } detail: {
            if let b = store.current {
                BottleView(bottle: b).id(b.id)
            } else {
                ContentUnavailableView(L("Nessun ambiente", "No bottles"), systemImage: "shippingbox",
                                       description: Text(L("Crea un ambiente Windows con il pulsante +", "Create a bottle with the + button")))
            }
        }
        .overlay(alignment: .bottom) { StatusBanner() }
        .sheet(isPresented: $showNew) { NewBottleSheet() }
        .modifier(TrashBottleAlert(bottle: $toTrash))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.reload() }
        .tint(.varco)
        .id(lang)   // redraw everything when the language changes
    }

}

/// Confirmation before moving a bottle to the Trash
struct TrashBottleAlert: ViewModifier {
    @EnvironmentObject var store: Store
    @Binding var bottle: Bottle?
    func body(content: Content) -> some View {
        content.alert(L("Spostare \"\(bottle?.name ?? "")\" nel Cestino?", "Move \"\(bottle?.name ?? "")\" to the Trash?"),
                      isPresented: Binding(get: { bottle != nil }, set: { if !$0 { bottle = nil } }), presenting: bottle) { b in
            Button(L("Sposta nel Cestino", "Move to Trash"), role: .destructive) { Task { await store.trash(b) } }
            Button(L("Annulla", "Cancel"), role: .cancel) {}
        } message: { _ in
            Text(L("L'ambiente, con i programmi e i giochi installati dentro, finisce nel Cestino: puoi recuperarlo da lì finché non lo svuoti. Le librerie di Steam su dischi esterni non vengono toccate.",
                   "The bottle, with the programs and games installed in it, goes to the Trash: you can restore it from there until you empty it. Steam libraries on external drives are not touched."))
        }
    }
}

struct StatusBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let text = store.busy ?? store.message {
            HStack(spacing: 8) {
                if store.busy != nil { ProgressView().controlSize(.small) }
                Text(text)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct BottleView: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle
    @State private var games: [Game] = []
    @State private var programs: [Program] = []
    @State private var settings = BottleSettings()
    /// Last state read from disk or saved: it is saved only when the user changes something.
    @State private var savedSettings = BottleSettings()
    /// FPS limit of games without their own value, including future downloads (-1 = not read yet)
    @State private var defaultFPS = -1
    @State private var showLog = false
    @State private var launchers: Set<String> = []
    @State private var toTrash: Bottle?
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if bottle.hasSteam { library } else { installSteam }
                storesSection
                programsSection
                settingsSection
                tools
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(bottle.name)
        .onAppear(perform: refresh)
        .onReceive(ticker) { _ in reloadContent() }
        .onReceive(NotificationCenter.default.publisher(for: .varcoReload)) { _ in reloadContent() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadContent() }
        .onChange(of: settings) { _, new in save(new) }
        .sheet(isPresented: $showLog) { LogView(bottle: bottle) }
        .modifier(TrashBottleAlert(bottle: $toTrash))
        .toolbar {
            ToolbarItem {
                Button { refresh() } label: { Label(L("Aggiorna", "Refresh"), systemImage: "arrow.clockwise") }
            }
        }
    }

    private func refresh() {
        reloadContent()
        if bottle.hasSteam {
            defaultFPS = Int(bottle.gamePrefs()["default.fps"] ?? "0") ?? 0
        }
        let loaded = bottle.settings()
        savedSettings = loaded      // this first, so onChange doesn't save again
        settings = loaded
    }

    private func reloadContent() {
        let g = bottle.games(), p = bottle.programs()
        // a game that just finished downloading: "ready" notice
        if let ready = g.first(where: { ng in ng.installed && games.contains { $0.id == ng.id && !$0.installed } }) {
            let note = L("\(ready.name) è pronto: buon divertimento!", "\(ready.name) is ready to play!")
            store.message = note
            Task { try? await Task.sleep(for: .seconds(6)); if store.message == note { store.message = nil } }
        }
        if g != games { games = g }
        if p != programs { programs = p }
        let l = bottle.installedLaunchers()
        if l != launchers { launchers = l }
    }

    private func save(_ new: BottleSettings) {
        let old = savedSettings
        guard new != old else { return }          // loading from disk: nothing to save
        var pairs: [(String, String)] = []
        if old.engine != new.engine { pairs.append(("ENGINE", new.engine)) }
        if old.hud != new.hud { pairs.append(("HUD", new.hud ? "1" : "0")) }
        if old.msync != new.msync { pairs.append(("MSYNC", new.msync ? "1" : "0")) }
        if old.retina != new.retina { pairs.append(("RETINA", new.retina ? "1" : "0")) }
        if old.dxr != new.dxr { pairs.append(("DXR", new.dxr ? "1" : "0")) }
        if old.metalfx != new.metalfx { pairs.append(("METALFX", new.metalfx ? "1" : "0")) }
        if old.cmdctrl != new.cmdctrl { pairs.append(("CMDCTRL", new.cmdctrl ? "1" : "0")) }
        if old.optalt != new.optalt { pairs.append(("OPTALT", new.optalt ? "1" : "0")) }
        if old.dpi != new.dpi { pairs.append(("DPI", String(new.dpi))) }
        savedSettings = new
        store.set(pairs, in: bottle)
    }

    private var engineDescription: String {
        switch settings.engine {
        case "cx26": return L("Motore Varco · D3DMetal (DirectX 11/12)", "Varco engine · D3DMetal (DirectX 11/12)")
        case "gptk": return "Game Porting Toolkit · D3DMetal (DirectX 11/12)"
        default: return "Wine 11 · DXMT (DirectX 9/10/11)"
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ArchIcon(size: 34)
            .frame(width: 56, height: 56)
            .background(Color.varco.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name).font(.title.bold())
                Text(engineDescription).foregroundStyle(.secondary)
            }
            Spacer()
            if bottle.hasSteam && store.steamRunning {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(L("Steam aperto", "Steam running")).foregroundStyle(.secondary)
                }
                Button(L("Chiudi Steam", "Quit Steam")) {
                    store.launch(["steam", bottle.name, "-shutdown"], note: L("Chiusura di Steam…", "Quitting Steam…"))
                }
                .controlSize(.large)
            } else if bottle.hasSteam {
                Button { store.openSteam(bottle) } label: { Label(L("Apri Steam", "Open Steam"), systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Giochi Steam", "Steam games")).font(.title3.bold())
            if games.isEmpty {
                Text(L("Nessun gioco installato. Apri Steam per scaricarne uno: comparirà qui da solo.", "No games installed. Open Steam to download one: it will show up here automatically.")).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(games) { g in GameCard(bottle: bottle, game: g) }
                }
            }
        }
    }

    /// Bottle without Steam: installed with one click (Valve's official installer)
    private var installSteam: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Giochi Steam", "Steam games")).font(.title3.bold())
            Text(L("Steam non è ancora installato in questo ambiente. Varco scarica l'installer ufficiale da Valve: segui i passaggi e accedi con il tuo account, poi i tuoi giochi compariranno qui da soli.",
                   "Steam isn't installed in this bottle yet. Varco downloads the official installer from Valve: follow the steps and sign in, then your games will show up here automatically."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button {
                Task {
                    let out = await store.run(["install-steam", bottle.name], status: L("Download di Steam…", "Downloading Steam…"))
                    store.message = out.contains("started") ? L("Installer di Steam avviato", "Steam installer started") : L("Installazione di Steam non riuscita", "Steam installation failed")
                }
            } label: { Label(L("Installa Steam", "Install Steam"), systemImage: "arrow.down.circle.fill") }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    /// Other stores: needed for games bought there and for Steam games that require them
    private var storesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Altri negozi", "Other stores")).font(.title3.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(Launcher.all) { l in LauncherRow(bottle: bottle, launcher: l, installed: launchers.contains(l.id)) }
            }
            Text(L("Per i giochi comprati su questi negozi, e per i giochi Steam che ne richiedono uno (per esempio Ubisoft Connect o EA app). L'installer viene scaricato dal sito ufficiale del negozio. I giochi GOG non hanno bisogno di un launcher: dalla tua libreria su gog.com scarica l'installer offline del gioco e aprilo con Installa….",
                   "For games bought on these stores, and for Steam games that require one (for example Ubisoft Connect or the EA app). The installer is downloaded from the store's official website. GOG games don't need a launcher: download the game's offline installer from your gog.com library and open it with Install…."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var programsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Programmi Windows", "Windows programs")).font(.title3.bold())
            if !programs.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(programs) { p in ProgramRow(bottle: bottle, program: p) }
                }
            }
            HStack(spacing: 10) {
                Button { pickExe(install: true) } label: { Label(L("Installa…", "Install…"), systemImage: "square.and.arrow.down") }
                Button { pickExe(install: false) } label: { Label(L("Esegui .exe…", "Run .exe…"), systemImage: "play.rectangle") }
            }
            .controlSize(.large)
            Text(L("Scegli un file .exe o .msi dal Mac: verrà avviato dentro questo ambiente. I programmi installati compaiono qui automaticamente.", "Pick an .exe or .msi file on your Mac: it runs inside this bottle. Installed programs show up here automatically."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Impostazioni", "Settings")).font(.title3.bold())
            Form {
                Picker(L("Motore", "Engine"), selection: $settings.engine) {
                    EngineChoices(current: settings.engine)
                }
                Toggle(L("Mostra FPS (HUD Metal)", "Show FPS (Metal HUD)"), isOn: $settings.hud)
                Toggle(L("Sincronizzazione veloce (MSync)", "Fast synchronization (MSync)"), isOn: $settings.msync)
                Toggle(L("Risoluzione Retina piena", "Full Retina resolution"), isOn: $settings.retina)
                Picker(L("Dimensione dell'interfaccia", "Interface size"), selection: Binding(get: { settings.dpi == 0 ? 96 : settings.dpi }, set: { settings.dpi = $0 })) {
                    Text("100%").tag(96)
                    Text("150%").tag(144)
                    Text(L("200% (consigliato con Retina)", "200% (recommended with Retina)")).tag(192)
                }
                Toggle("Ray tracing (D3DMetal)", isOn: $settings.dxr)
                    .disabled(settings.engine == "wine11")
                Toggle(L("DLSS → MetalFX (la GPU appare come NVIDIA ai giochi)", "DLSS → MetalFX (the GPU looks like NVIDIA to games)"), isOn: $settings.metalfx)
                    .disabled(settings.engine != "cx26")
                Toggle(L("Usa ⌘ come Ctrl", "Use ⌘ as Ctrl"), isOn: $settings.cmdctrl)
                Toggle(L("Usa ⌥ come Alt", "Use ⌥ as Alt"), isOn: $settings.optalt)
                if bottle.hasSteam && defaultFPS >= 0 {
                    Picker(L("Limite FPS dei giochi", "Game FPS limit"), selection: Binding(get: { defaultFPS }, set: { v in
                        defaultFPS = v
                        Task { await store.run(["fps", bottle.name, "default", String(v)]); NotificationCenter.default.post(name: .varcoReload, object: nil) }
                    })) {
                        Text(L("Nessun limite", "No limit")).tag(0)
                        ForEach([30, 40, 60, 120], id: \.self) { Text("\($0) fps").tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 560)
            .scrollDisabled(true)
            Text(L("Il limite FPS vale per tutti i giochi che non ne hanno uno proprio, anche quelli che scaricherai: per cambiarlo su un solo gioco, clic destro sulla copertina → Limite FPS.", "The FPS limit applies to every game without its own limit, including the ones you'll download: to change it for one game, right-click its cover → FPS limit."))
                .font(.callout).foregroundStyle(.secondary)
            Text(EngineChoices.hasWine11 || settings.engine == "wine11"
                 ? L("Le modifiche valgono dal prossimo avvio. Con Wine 11 i giochi che richiedono DirectX 12 non partono: in quel caso usa il motore Varco + D3DMetal.", "Changes apply from the next launch. With Wine 11, games that require DirectX 12 won't start: use the Varco + D3DMetal engine for those.")
                 : L("Le modifiche valgono dal prossimo avvio.", "Changes apply from the next launch."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Strumenti", "Tools")).font(.title3.bold())
            HStack(spacing: 10) {
                Button { NSWorkspace.shared.open(bottle.url.appendingPathComponent("drive_c")) } label: {
                    Label(L("Disco C:", "C: drive"), systemImage: "internaldrive")
                }
                Button { store.launch(["config", bottle.name], note: L("Configurazione Wine in apertura…", "Opening Wine configuration…")) } label: {
                    Label(L("Configurazione Wine", "Wine configuration"), systemImage: "slider.horizontal.3")
                }
                Button { store.launch(["regedit", bottle.name], note: L("Editor del registro in apertura…", "Opening the registry editor…")) } label: {
                    Label(L("Registro", "Registry"), systemImage: "list.bullet.rectangle")
                }
                Button { showLog = true } label: { Label("Log", systemImage: "doc.text") }
                Button(role: .destructive) {
                    store.launch(["kill", bottle.name], note: L("Tutti i programmi dell'ambiente sono stati chiusi", "All programs in this bottle were closed"))
                } label: { Label(L("Chiudi tutto", "Quit all"), systemImage: "xmark.octagon") }
            }
            HStack(spacing: 10) {
                Button { reportProblem() } label: { Label(L("Segnala un problema…", "Report a problem…"), systemImage: "exclamationmark.bubble") }
                Button(role: .destructive) { toTrash = bottle } label: { Label(L("Sposta nel Cestino…", "Move to Trash…"), systemImage: "trash") }
            }
        }
    }

    /// Copies the useful details (versions, settings, last log lines) and opens GitHub issues
    private func reportProblem() {
        Task {
            let info = await store.diagnostics(for: bottle)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
            NSWorkspace.shared.open(VarcoRelease.newIssue)
            store.message = L("Informazioni copiate: incollale nella segnalazione su GitHub", "Details copied: paste them into the report on GitHub")
            try? await Task.sleep(for: .seconds(6)); store.message = nil
        }
    }

    private func pickExe(install: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe"), UTType(filenameExtension: "msi")].compactMap { $0 }
        panel.directoryURL = home.appendingPathComponent("Downloads")
        panel.prompt = install ? L("Installa", "Install") : L("Esegui", "Run")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.launch([install ? "install" : "run", bottle.name, url.path], note: L("\(url.lastPathComponent) in avvio…", "Launching \(url.lastPathComponent)…"))
    }
}

/// Engines in the menu: only the installed ones. Game Porting Toolkit (Wine 7.7, Steam doesn't work) is no longer offered,
/// it stays visible only if a bottle already uses it.
struct EngineChoices: View {
    let current: String
    private static func installed(_ dir: String) -> Bool {
        FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("engines/\(dir)").path)
    }
    private func installed(_ dir: String) -> Bool { Self.installed(dir) }
    static var hasWine11: Bool { installed("wine-11.17") }
    var body: some View {
        if installed("cx26") || current == "cx26" {
            Text(L("Varco + D3DMetal (consigliato)", "Varco + D3DMetal (recommended)")).tag("cx26")
        }
        if installed("wine-11.17") || current == "wine11" {
            Text(L("Alternativo: Wine 11 + DXMT (fino a DirectX 11)", "Alternative: Wine 11 + DXMT (up to DirectX 11)")).tag("wine11")
        }
        if current == "gptk" {
            Text(L("Game Porting Toolkit (sconsigliato)", "Game Porting Toolkit (not recommended)")).tag("gptk")
        }
    }
}

struct GameCard: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle
    let game: Game
    @State private var hover = false
    @State private var askDX12 = false
    @State private var dxPref: String?
    @State private var padMode = "ps"
    @State private var fpsError: String?
    private var fpsLimit: Int? { game.fps }
    private var running: Bool { game.folder.map { store.runningDirs.contains($0.lastPathComponent.lowercased()) } ?? false }
    /// DirectX label: for games that support 11 and 12 it shows the one chosen in Varco
    private var badgeText: String? {
        if dx == .dx11And12, let p = dxPref { return p == "dx12" ? "DX12" : "DX11" }
        return dx.badge
    }

    private var dx: DirectX { store.directX(for: game) }
    /// true if the bottle's engine doesn't support DirectX 12 (Wine 11 + DXMT only)
    private var engineLacksDX12: Bool { bottle.settings().engine == "wine11" }

    /// Launch options: per game, or automatic based on DirectX.
    private var launchArgs: [String] {
        switch game.id {
        case "292030":   // The Witcher 3: skip REDlauncher (launcher-configuration.json picks the version)
            return ["--launcher-skip", dxPref == "dx12" && !engineLacksDX12 ? "-dx12" : "-dx11"]
        default:
            if let pref = dxPref, dx == .dx11And12 { return [engineLacksDX12 ? "-dx11" : "-\(pref)"] }
            // With Wine 11 + DXMT, games that support both versions start in DirectX 11
            return (engineLacksDX12 && dx == .dx11And12) ? ["-dx11"] : []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if let art = game.art, let img = NSImage(contentsOf: art) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(game.name).font(.headline).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                    }
                    if hover && game.installed {
                        Color.black.opacity(0.35)
                        Image(systemName: "play.circle.fill").font(.system(size: 48)).foregroundStyle(.white)
                    }
                }
                .frame(width: 150, height: 225)

                if let badge = badgeText {
                    Text(badge)
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(dx.color, in: Capsule())
                        .padding(6)
                } else if game.installed {
                    ProgressView().controlSize(.mini).padding(8)
                        .help(L("Analisi della versione DirectX in corso…", "Detecting the DirectX version…"))
                }
            }
            .frame(width: 150, height: 225)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(radius: hover ? 8 : 3, y: 2)
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hover)
            .onHover { hover = $0 }
            .onTapGesture { play() }

            Text(game.name).font(.callout.weight(.medium)).lineLimit(2).frame(width: 150, alignment: .leading)
            if running {
                Label(L("In esecuzione", "Running"), systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
                    .labelStyle(.titleAndIcon).imageScale(.small)
            } else if game.installed, let fps = fpsLimit {
                Text(fps > 0 ? "max \(fps) fps" : L("Nessun limite FPS", "No FPS limit")).font(.caption).foregroundStyle(.secondary)
            }
            if !game.installed, let p = game.progress {
                ProgressView(value: p).frame(width: 150)
                Text(L("Download \(Int(p * 100))%", "Downloading \(Int(p * 100))%")).font(.caption).foregroundStyle(.secondary)
            } else if !game.installed {
                Text(L("Da aggiornare in Steam", "Needs an update in Steam")).font(.caption).foregroundStyle(.orange)
            } else if dx == .dx12Only && engineLacksDX12 {
                Text(L("Richiede DirectX 12: cambia motore", "Requires DirectX 12: change engine")).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear {
            dxPref = bottle.dxPreference(for: game.id)
            padMode = bottle.gamePrefs()["\(game.id).pad"] ?? (xinputByDefault.contains(game.id) ? "xbox" : "ps")
        }
        .contextMenu {
            Button(L("Gioca", "Play")) { play() }
            if fpsSupported {
                Menu(L("Limite FPS", "FPS limit") + (fpsLimit.map { $0 > 0 ? " (\($0))" : L(" (nessuno)", " (none)") } ?? "")) {
                    ForEach(fpsChoices, id: \.self) { value in
                        Button { setFPS(value) } label: {
                            Label(fpsLabel(value), systemImage: fpsLimit == value ? "checkmark" : "")
                        }
                    }
                }
            }
            if fpsSupported {
                Menu(L("Controller", "Controller")) {
                    Button { setPad("ps") } label: { Label("PlayStation (DualSense)", systemImage: padMode == "ps" ? "checkmark" : "") }
                    Button { setPad("xbox") } label: {
                        Label(L("Xbox (per i giochi che non vedono il DualSense)", "Xbox (for games that don't see the DualSense)"), systemImage: padMode == "xbox" ? "checkmark" : "")
                    }
                }
            }
            if dx == .dx11And12 {
                Divider()
                Button { setDX("dx11") } label: {
                    Label(L("Usa DirectX 11 (più leggero)", "Use DirectX 11 (lighter)"), systemImage: dxPref != "dx12" ? "checkmark" : "")
                }
                Button { setDX("dx12") } label: {
                    Label(L("Usa DirectX 12", "Use DirectX 12"), systemImage: dxPref == "dx12" ? "checkmark" : "")
                }
                .disabled(engineLacksDX12)
                Divider()
            }
            Button(L("Crea icona nel Dock/Applicazioni", "Add to Dock/Applications")) {
                Task {
                    let out = await store.run(["app", bottle.name, game.name, "game", game.id] + launchArgs)
                    store.message = out.contains("Created:") ? L("App creata in ~/Applications/Varco", "App created in ~/Applications/Varco")
                                                           : L("Non è stato possibile creare l'app", "Couldn't create the app")
                }
            }
            Button(L("Apri cartella del gioco", "Open game folder")) {
                NSWorkspace.shared.open(game.folder ?? bottle.steamURL.appendingPathComponent("steamapps/common"))
            }
        }
        .help(helpText)
        .alert(L("Limite FPS", "FPS limit"), isPresented: Binding(get: { fpsError != nil }, set: { if !$0 { fpsError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(fpsError ?? "") }
        .alert(L("\(game.name) richiede DirectX 12", "\(game.name) requires DirectX 12"), isPresented: $askDX12) {
            Button(L("Prova comunque", "Try anyway")) { store.play(game, in: bottle, args: launchArgs) }
            Button(L("Annulla", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Il motore Wine 11 di questo ambiente supporta solo fino a DirectX 11. Imposta il motore \"Varco + D3DMetal\" nelle impostazioni dell'ambiente.", "This bottle's Wine 11 engine only supports up to DirectX 11. Choose the \"Varco + D3DMetal\" engine in the bottle settings."))
        }
    }

    private var helpText: String {
        guard game.installed else { return L("Apri Steam per completare l'aggiornamento", "Open Steam to finish the update") }
        switch dx {
        case .dx12Only: return L("Questo gioco richiede DirectX 12", "This game requires DirectX 12")
        case .dx11And12: return engineLacksDX12 ? L("Supporta DirectX 11 e 12: parte in DirectX 11", "Supports DirectX 11 and 12: starts in DirectX 11") : L("DirectX 11 e 12", "DirectX 11 and 12")
        case .dx11OrOlder: return L("DirectX 11 o precedente", "DirectX 11 or older")
        case .unknown: return L("Clic per giocare", "Click to play")
        }
    }

    /// FPS limit for every installed game ("varco fps"): The Witcher 3 and Death Stranding use their own settings,
    /// the others Varco's limiter in the engine ("no limit" too)
    private var fpsSupported: Bool { game.installed }
    private var nativeFPS: Bool { ["292030", "1850570"].contains(game.id) }
    private var fpsChoices: [Int] { nativeFPS ? [30, 40, 60, 120] : [30, 40, 60, 120, 0] }

    private func fpsLabel(_ value: Int) -> String {
        switch value {
        case 0: L("Nessun limite", "No limit")
        case 30, 48: L("\(value) fps (silenzioso)", "\(value) fps (quiet)")
        case 40, 50: L("\(value) fps (equilibrato)", "\(value) fps (balanced)")
        case 60: L("60 fps (fluido)", "60 fps (smooth)")
        default: L("\(value) fps (massimo, ventole alte)", "\(value) fps (maximum, loud fans)")
        }
    }

    private func setFPS(_ value: Int) {
        Task {
            let out = await store.run(["fps", bottle.name, game.id, String(value)])
            if out.contains("Close the game first") {
                fpsError = L("Chiudi prima \(game.name), poi cambia il limite FPS: altrimenti il gioco lo sovrascrive all'uscita.", "Quit \(game.name) first, then change the FPS limit: otherwise the game overwrites it when it closes.")
            } else if out.contains("not found") {
                fpsError = L("Avvia \(game.name) almeno una volta: il limite FPS sta nelle impostazioni del gioco, che vengono create al primo avvio.", "Launch \(game.name) once first: the FPS limit lives in the game's settings, which are created on first launch.")
            } else if !out.contains("FPS limit set") && !out.contains("No FPS limit") {
                fpsError = L("Il limite FPS non è stato cambiato.", "The FPS limit was not changed.")
            } else {
                NotificationCenter.default.post(name: .varcoReload, object: nil)
                store.message = value > 0 ? L("Limite FPS: \(value) (vale dal prossimo avvio)", "FPS limit: \(value) (applies from next launch)")
                                          : L("Nessun limite FPS (dal prossimo avvio)", "No FPS limit (from next launch)")
                try? await Task.sleep(for: .seconds(4))
                store.message = nil
            }
        }
    }

    private func setPad(_ mode: String) {
        Task {
            let out = await store.run(["pad", bottle.name, game.id, mode])
            guard out.contains("Controller:") else { store.message = L("Controller non cambiato", "Controller not changed"); return }
            padMode = mode
            store.message = mode == "xbox" ? L("Controller Xbox per \(game.name) (dal prossimo avvio)", "Xbox controller for \(game.name) (from next launch)")
                                           : L("Controller PlayStation per \(game.name) (dal prossimo avvio)", "PlayStation controller for \(game.name) (from next launch)")
            try? await Task.sleep(for: .seconds(4)); store.message = nil
        }
    }

    private func setDX(_ mode: String) {
        Task {
            await store.run(["dxmode", bottle.name, game.id, mode])
            dxPref = mode
            let v = mode == "dx12" ? "12" : "11"
            store.message = L("DirectX \(v) impostato: vale dal prossimo avvio", "DirectX \(v) set: applies from next launch")
            try? await Task.sleep(for: .seconds(5))
            store.message = nil
        }
    }

    private func play() {
        guard game.installed else {
            store.openSteam(bottle)
            return
        }
        if dx == .dx12Only && engineLacksDX12 {
            askDX12 = true
            return
        }
        store.play(game, in: bottle, args: launchArgs)
    }
}

struct LauncherRow: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle
    let launcher: Launcher
    let installed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: launcher.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            Text(launcher.name).lineLimit(1)
            Spacer()
            if let page = launcher.page {
                Button(L("Apri GOG.com", "Open GOG.com")) { NSWorkspace.shared.open(page) }
                    .help(L("I giochi GOG si installano senza GOG Galaxy: nella tua libreria su gog.com scegli il gioco → installer offline, poi aprilo con Installa… qui sotto.",
                            "GOG games install without GOG Galaxy: in your gog.com library pick the game → offline installer, then open it with Install… below."))
            } else if installed {
                Button(L("Apri", "Open")) {
                    store.launch(["store", bottle.name, launcher.id], note: L("\(launcher.name) in avvio…", "Launching \(launcher.name)…"))
                }
            } else {
                Button(L("Installa", "Install")) {
                    Task {
                        let out = await store.run(["install-store", bottle.name, launcher.id], status: L("Download di \(launcher.name)…", "Downloading \(launcher.name)…"))
                        store.message = out.contains("started") ? L("Installer di \(launcher.name) avviato: segui i passaggi", "\(launcher.name) installer started: follow the steps")
                                                               : L("Download di \(launcher.name) non riuscito", "Couldn't download \(launcher.name)")
                    }
                }
            }
        }
        .padding(10)
        .background(AnyShapeStyle(.quaternary.opacity(0.5)), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ProgramRow: View {
    @EnvironmentObject var store: Store
    let bottle: Bottle
    let program: Program
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "app.dashed").font(.title2).foregroundStyle(.tint).frame(width: 32)
            Text(program.name).lineLimit(1)
            Spacer()
            Image(systemName: "play.fill").opacity(hover ? 1 : 0.3)
        }
        .padding(10)
        .background(hover ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { store.runProgram(program.path, in: bottle, name: program.name) }
        .contextMenu {
            Button(L("Avvia", "Launch")) { store.runProgram(program.path, in: bottle, name: program.name) }
            Button(L("Crea icona nel Dock/Applicazioni", "Add to Dock/Applications")) {
                Task {
                    let out = await store.run(["app", bottle.name, program.name, "run", program.path])
                    store.message = out.contains("Created:") ? L("App creata in ~/Applications/Varco", "App created in ~/Applications/Varco")
                                                           : L("Non è stato possibile creare l'app", "Couldn't create the app")
                }
            }
            Button(L("Mostra nel Finder", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: program.path)]) }
        }
    }
}

struct NewBottleSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var engine = "cx26"
    @State private var working = false
    @State private var error: String?

    private var valid: Bool {
        !name.isEmpty && name.range(of: "^[A-Za-z0-9 _-]+$", options: .regularExpression) != nil
            && !store.varcoBottles.contains { $0.name == name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Nuovo ambiente Windows", "New bottle")).font(.title2.bold())
            Text(L("Un ambiente è un Windows separato, con i suoi programmi e le sue impostazioni. Conviene usarne uno per gioco o per gruppo di programmi.", "A bottle is a separate Windows environment. Use one per game or per group of programs."))
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(L("Nome", "Name"), text: $name, prompt: Text(L("es. Giochi", "e.g. Games")))
                Picker(L("Motore", "Engine"), selection: $engine) {
                    EngineChoices(current: engine)
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                if working { ProgressView().controlSize(.small); Text(L("Creazione in corso, circa un minuto…", "Creating, about a minute…")).foregroundStyle(.secondary) }
                Spacer()
                Button(L("Annulla", "Cancel")) { dismiss() }.disabled(working)
                Button(L("Crea", "Create")) { create() }.buttonStyle(.borderedProminent).disabled(!valid || working)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func create() {
        working = true
        Task {
            let out = await store.run(["create", name, engine])
            working = false
            store.reload()
            if out.contains("Done:"), let b = store.varcoBottles.first(where: { $0.name == name }) {
                store.selection = b.id
                dismiss()
            } else {
                error = L("Creazione non riuscita: ", "Creation failed: ") + String(out.suffix(200))
            }
        }
    }
}

struct LogView: View {
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(L("Log di \(bottle.name)", "\(bottle.name) log")).font(.title3.bold())
                Spacer()
                Button(L("Aggiorna", "Refresh")) { load() }
                Button(L("Chiudi", "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                Text(text.isEmpty ? L("Nessun log.", "No log yet.") : text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .padding(20)
        .frame(width: 760, height: 480)
        .onAppear(perform: load)
    }

    private func load() {
        let url = rootURL.appendingPathComponent("logs/\(bottle.name).log")
        // only the last half megabyte: a log can grow huge
        var all = ""
        if let h = try? FileHandle(forReadingFrom: url) {
            let end = (try? h.seekToEnd()) ?? 0
            try? h.seek(toOffset: end > 512_000 ? end - 512_000 : 0)
            all = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
            try? h.close()
        }
        text = all.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("fixme:") }.suffix(300).joined(separator: "\n")
    }
}
