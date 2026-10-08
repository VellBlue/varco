// varco-tool: Varco's game settings (FPS limit and DirectX version). No dependencies: it is built by
// scripts/build-app.sh (or: swiftc -O -o cli/tools/varco-tool cli/tools/varco-tool.swift).
//
// usage: varco-tool fps <bottle> <steam-appid>|default [value]   show or change (0 = no limit)
//        varco-tool fps <bottle> --write-conf                    regenerate varco-fps.conf (also done at every start)
//        varco-tool dxmode <bottle> <steam-appid> [dx11|dx12] <0|1 Steam running>
//        varco-tool pad <bottle> <steam-appid> [ps|xbox]           how the game sees the DualSense
//
// FPS limit: each game uses the best method it has.
//  - The Witcher 3 and Death Stranding have a limit in their own settings: that one is changed;
//  - every other game (including the ones downloaded later) uses Varco's limiter in the Wine engine
//    (dlls/winemac.drv/d3dmetal*.{c,m}), which reads <bottle>/varco-fps.conf: "<game folder>\t<fps>" and "*\t<fps>".
// Preferences live in <bottle>/varco-games.conf as "<appid>.fps=N" and "default.fps=N".
import Foundation

let NATIVE: Set<String> = ["292030", "1850570"]   // games with their own limiter in their settings
let fm = FileManager.default

// MARK: - Helpers

func join(_ base: String, _ parts: String...) -> String {
    parts.reduce(base) { ($0 as NSString).appendingPathComponent($1) }
}

func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
func exists(_ p: String) -> Bool { fm.fileExists(atPath: p) }

func realPath(_ p: String) -> String {
    guard let r = realpath(p, nil) else { return p }
    defer { free(r) }
    return String(cString: r)
}

/// The visible entries of a folder (like glob's "*"), in alphabetical order
func entries(_ dir: String) -> [String] {
    ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
}

/// Text to search (UTF-8, invalid bytes don't matter)
func readLoose(_ p: String) -> String? { fm.contents(atPath: p).map { String(decoding: $0, as: UTF8.self) } }
/// Text to edit byte by byte (Latin-1: every byte stays identical when written back)
func readBytes(_ p: String) -> String? { fm.contents(atPath: p).flatMap { String(data: $0, encoding: .isoLatin1) } }
func writeBytes(_ p: String, _ s: String) throws { try s.data(using: .isoLatin1)!.write(to: URL(fileURLWithPath: p)) }
func writeAtomic(_ p: String, _ s: String) throws { try Data(s.utf8).write(to: URL(fileURLWithPath: p), options: .atomic) }

func rx(_ pattern: String, lines: Bool = false) -> NSRegularExpression {
    try! NSRegularExpression(pattern: pattern, options: lines ? [.anchorsMatchLines] : [])
}

extension String {
    var ns: NSString { self as NSString }
    var full: NSRange { NSRange(location: 0, length: ns.length) }
    /// The groups of the first match
    func match(_ r: NSRegularExpression) -> [String]? {
        guard let m = r.firstMatch(in: self, range: full) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }
    /// Group 1 of every match
    func all(_ r: NSRegularExpression) -> [String] {
        r.matches(in: self, range: full).map { ns.substring(with: $0.range(at: 1)) }
    }
    /// Replaces every match with the text f builds from the groups; also returns how many there were
    func replacing(_ r: NSRegularExpression, _ f: ([String]) -> String) -> (String, Int) {
        let ms = r.matches(in: self, range: full)
        var out = "", last = 0
        for m in ms {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f((0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) })
            last = m.range.upperBound
        }
        return (out + ns.substring(from: last), ms.count)
    }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Like Python's int(v or 0): empty or invalid = 0
func toInt(_ v: String?) -> Int { Int((v ?? "").trimmed) ?? 0 }

func copyOnce(_ path: String, _ suffix: String) {
    if !exists(path + suffix) { try? fm.copyItem(atPath: path, toPath: path + suffix) }
}

func fail(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8)); exit(code)
}

// MARK: - Steam libraries

func steamDir(_ bottle: String) -> String { join(bottle, "drive_c/Program Files (x86)/Steam") }

/// The libraries listed in libraryfolders.vdf, as Mac paths (E:\SteamLibrary → dosdevices/e:/SteamLibrary)
func vdfLibraries(_ bottle: String) -> [String] {
    guard let text = readLoose(join(steamDir(bottle), "steamapps/libraryfolders.vdf")) else { return [] }
    return text.all(rx(#""path"\s+"([^"]+)""#)).compactMap { raw in
        let win = raw.replacingOccurrences(of: "\\\\", with: "\\")
        let c = Array(win)
        guard c.count >= 2, c[1] == ":" else { return nil }
        return join(bottle, "dosdevices", String(c[0]).lowercased() + ":") + String(win.dropFirst(2)).replacingOccurrences(of: "\\", with: "/")
    }
}

func libraries(_ bottle: String) -> [String] {
    ([steamDir(bottle)] + vdfLibraries(bottle)).filter { isDir(join($0, "steamapps")) }
}

/// appid → (install folder, library) for every game in every library
func installDirs(_ bottle: String) -> [String: (dir: String, lib: String)] {
    var out: [String: (dir: String, lib: String)] = [:]
    let appid = rx(#""appid"\s+"(\d+)""#), installdir = rx(#""installdir"\s+"([^"]+)""#)
    for lib in libraries(bottle) {
        let apps = join(lib, "steamapps")
        for f in entries(apps) where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
            guard let text = readLoose(join(apps, f)), let a = text.match(appid), let d = text.match(installdir) else { continue }
            if out[a[1]] == nil { out[a[1]] = (d[1], lib) }
        }
    }
    return out
}

// MARK: - Preferences (varco-games.conf), in order

struct Prefs {
    var keys: [String] = []
    var values: [String: String] = [:]
    subscript(k: String) -> String? {
        get { values[k] }
        set { if values[k] == nil { keys.append(k) }; values[k] = newValue }
    }
}

func prefsPath(_ bottle: String) -> String { join(bottle, "varco-games.conf") }

func readPrefs(_ bottle: String) -> Prefs {
    var p = Prefs()
    guard let text = try? String(contentsOfFile: prefsPath(bottle), encoding: .utf8) else { return p }
    for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
        guard let eq = line.firstIndex(of: "=") else { continue }
        p[String(line[..<eq])] = String(line[line.index(after: eq)...])
    }
    return p
}

func writePrefs(_ bottle: String, _ p: Prefs) throws {
    try writeAtomic(prefsPath(bottle), p.keys.map { "\($0)=\(p.values[$0]!)\n" }.joined())
}

// MARK: - FPS limit

func writeConf(_ bottle: String) throws {
    let prefs = readPrefs(bottle), dirs = installDirs(bottle)
    var lines = ["*\t\(toInt(prefs["default.fps"] ?? "0"))"]
    for k in prefs.keys where k.hasSuffix(".fps") && k != "default.fps" {
        if let d = dirs[String(k.dropLast(4))] { lines.append("\(d.dir.lowercased())\t\(toInt(prefs[k]))") }
    }
    try writeAtomic(join(bottle, "varco-fps.conf"), lines.joined(separator: "\n") + "\n")
}

/// The settings files of games with their own limiter, with the expression of the value (group 2)
func nativeTargets(_ bottle: String, _ appid: String) -> [(path: String, rx: NSRegularExpression)] {
    if appid == "292030" {
        let users = join(bottle, "drive_c/users")
        guard let first = entries(users).map({ join(users, $0, "Documents/The Witcher 3") }).first(where: isDir) else { return [] }
        let d = realPath(first)
        var files = [join(d, "user.settings"), join(d, "dx12user.settings")]
        if (try? String(contentsOfFile: prefsPath(bottle), encoding: .utf8))?.contains("292030=dx12") == true {
            files.reverse()   // the first file is the one of the version in use
        }
        return files.filter(exists).map { ($0, rx(#"^(LimitFPS=)(\d+)(\r?)$"#, lines: true)) }
    }
    if appid == "1850570", let info = installDirs(bottle)[appid] {
        let f = join(info.lib, "steamapps/common", info.dir, "settings.cfg")
        if exists(f) { return [(f, rx(#"^("limit_fps"\s+")(\d+)(")"#, lines: true))] }
    }
    return []
}

func nativeGet(_ bottle: String, _ appid: String) -> Int? {
    guard let t = nativeTargets(bottle, appid).first, let m = readBytes(t.path)?.match(t.rx) else { return nil }
    return Int(m[2])
}

func nativeSet(_ bottle: String, _ appid: String, _ val: Int) throws -> Int {
    var changed = 0
    for t in nativeTargets(bottle, appid) {
        guard let data = readBytes(t.path) else { continue }
        let (new, n) = data.replacing(t.rx) { $0[1] + String(val) + $0[3] }
        if n > 0 {
            copyOnce(t.path, ".bak-varco-fps")
            try writeBytes(t.path, new)
            changed += 1
        }
    }
    return changed
}

/// RDR2 used to be limited through the screen's Hz: back to 120 Hz, now Varco limits it
func rdr2FullRefresh(_ bottle: String) throws {
    let users = join(bottle, "drive_c/users")
    for u in entries(users) {
        let f = realPath(join(users, u, "Documents/Rockstar Games/Red Dead Redemption 2/Settings/system.xml"))
        guard let data = readBytes(f) else { continue }
        let new = data.replacing(rx(#"(<refreshRateNumerator value=")\d+(")"#)) { $0[1] + "120000" + $0[2] }.0
            .replacing(rx(#"(<refreshRateDenominator value=")\d+(")"#)) { $0[1] + "1000" + $0[2] }.0
        if new != data { try writeBytes(f, new) }
    }
}

func fps(_ a: [String]) throws {
    guard a.count >= 2 else { fail("usage: varco-tool fps <bottle> <steam-appid>|default|--write-conf [value]") }
    let bottle = a[0], appid = a[1], val = a.count > 2 ? a[2] : ""
    if appid == "--write-conf" { try writeConf(bottle); return }
    var prefs = readPrefs(bottle)
    if appid == "default" {
        if !val.isEmpty {
            guard let v = Int(val) else { fail("Invalid value: \(val)") }
            prefs["default.fps"] = String(v)
            try writePrefs(bottle, prefs); try writeConf(bottle)
            print(v != 0 ? "Default FPS limit: \(val)" : "No default FPS limit")
        } else {
            print(toInt(prefs["default.fps"] ?? "0"))
        }
        return
    }
    if val.isEmpty {
        if NATIVE.contains(appid), let v = nativeGet(bottle, appid) { print(v); return }
        print(toInt(prefs["\(appid).fps"] ?? prefs["default.fps"] ?? "0"))
        return
    }
    guard let v = Int(val) else { fail("Invalid value: \(val)") }
    if NATIVE.contains(appid) && v > 0, try nativeSet(bottle, appid, v) == 0 {
        print("Game settings file not found (start the game at least once)"); exit(1)
    }
    prefs["\(appid).fps"] = String(v)
    try writePrefs(bottle, prefs)
    if appid == "1174180" { try rdr2FullRefresh(bottle) }
    try writeConf(bottle)
    print(v != 0 ? "FPS limit set to \(v)" : "No FPS limit")
}

// MARK: - DirectX version

func dxmode(_ a: [String]) throws {
    guard a.count >= 4 else { fail("usage: varco-tool dxmode <bottle> <steam-appid> [dx11|dx12] <0|1>") }
    let bottle = a[0], appid = a[1], mode = a[2], steamRunning = a[3] == "1"
    let steam = steamDir(bottle), prefs = prefsPath(bottle)
    var cur: [String: String] = [:]
    for line in ((try? String(contentsOfFile: prefs, encoding: .utf8)) ?? "").split(whereSeparator: { $0.isNewline }) {
        let l = String(line).trimmed
        guard let eq = l.firstIndex(of: "=") else { continue }
        cur[String(l[..<eq])] = String(l[l.index(after: eq)...])
    }
    // look for the game in every Steam library (external drives too, e.g. E:\SteamLibrary)
    var libs = [steam]
    for unix in vdfLibraries(bottle) where !libs.map(realPath).contains(realPath(unix)) { libs.append(unix) }
    var gameDir: String?
    for lib in libs {
        if let text = readLoose(join(lib, "steamapps", "appmanifest_\(appid).acf")), let m = text.match(rx(#""installdir"\s+"([^"]+)""#)) {
            gameDir = join(lib, "steamapps/common", m[1]); break
        }
    }
    if mode.isEmpty { print(cur[appid] ?? "default"); return }
    guard mode == "dx11" || mode == "dx12" else { fail("Use dx11 or dx12") }
    let label = mode == "dx11" ? "DirectX 11" : "DirectX 12"
    var done: [String] = []
    // 1) CD Projekt games: the prelauncher's default version
    if let gameDir {
        let cfg = join(gameDir, "launcher-configuration.json")
        if var raw = try? String(contentsOfFile: cfg, encoding: .utf8) {
            if raw.hasPrefix("\u{FEFF}") { raw.removeFirst() }
            if raw.contains(label) {
                copyOnce(cfg, ".bak-varco")
                let new = raw.replacing(rx(#"("fallback"\s*:\s*")[^"]*(")"#)) { $0[1] + label + $0[2] }.0
                guard (try? JSONSerialization.jsonObject(with: Data(new.utf8))) != nil else { fail("invalid launcher-configuration.json") }
                try writeAtomic(cfg, new)
                done.append("launcher default version")
            }
        }
    }
    // 2) Steam launch options (only with Steam closed, otherwise Steam overwrites them)
    if steamRunning {
        done.append("Steam launch options NOT updated (Steam is running)")
    } else {
        let userdata = join(steam, "userdata")
        for u in entries(userdata) {
            let lc = join(userdata, u, "config/localconfig.vdf")
            guard let s = try? String(contentsOfFile: lc, encoding: .utf8) else { continue }
            let ns = s.ns
            guard let m = rx("(\"\(appid)\"\\s*\\{)").firstMatch(in: s, range: s.full) else { continue }
            // the brace that closes the game's block
            var depth = 0, j = m.range.upperBound - 1
            let open = UInt16(UInt8(ascii: "{")), close = UInt16(UInt8(ascii: "}"))
            for k in (m.range.upperBound - 1)..<ns.length {
                j = k
                let c = ns.character(at: k)
                if c == open { depth += 1 } else if c == close { depth -= 1; if depth == 0 { break } }
            }
            var body = ns.substring(with: NSRange(location: m.range.upperBound, length: j - m.range.upperBound))
            guard let lo = rx(#""LaunchOptions"\s*"([^"]*)""#).firstMatch(in: body, range: body.full) else { continue }
            let r = lo.range(at: 1)
            var opts = body.ns.substring(with: r).replacing(rx(#"\s*-dx1[12]\b"#)) { _ in "" }.0.trimmed
            opts = (opts + " -" + mode).trimmed
            body = body.ns.replacingCharacters(in: r, with: opts)
            copyOnce(lc, ".bak-varco")
            try writeAtomic(lc, ns.substring(to: m.range.upperBound) + body + ns.substring(from: j))
            done.append("Steam launch options")
        }
    }
    cur[appid] = mode
    try writeAtomic(prefs, cur.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }.map { "\($0)=\(cur[$0]!)\n" }.joined())
    print("\(label) set. Updated: " + (done.isEmpty ? "only the Varco preference" : done.joined(separator: ", ")))
}

// MARK: - Controller

/// Games that only read Xbox controllers (XInput): the DualSense shows up as an Xbox pad unless the user chose otherwise
let XINPUT_DEFAULT: Set<String> = ["1174180"]   // Red Dead Redemption 2

func pad(_ a: [String]) throws {
    guard a.count >= 2 else { fail("usage: varco-tool pad <bottle> <steam-appid> [ps|xbox]") }
    let bottle = a[0], appid = a[1], mode = a.count > 2 ? a[2] : ""
    var prefs = readPrefs(bottle)
    if mode.isEmpty { print(prefs["\(appid).pad"] ?? (XINPUT_DEFAULT.contains(appid) ? "xbox" : "ps")); return }
    guard mode == "ps" || mode == "xbox" else { fail("Use ps or xbox") }
    prefs["\(appid).pad"] = mode
    try writePrefs(bottle, prefs)
    print(mode == "xbox" ? "Controller: Xbox" : "Controller: PlayStation")
}

// MARK: -

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "fps": try fps(Array(args.dropFirst()))
    case "dxmode": try dxmode(Array(args.dropFirst()))
    case "pad": try pad(Array(args.dropFirst()))
    default: fail("usage: varco-tool fps|dxmode|pad ...")
    }
} catch {
    fail("Error: \(error.localizedDescription)")
}
