import Foundation

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ launch: String, _ args: [String], timeout: TimeInterval = 120) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

// MARK: - Sizing

enum Sizer {
    /// `du -sk` is dramatically faster than walking the tree in Swift, and it reports
    /// allocated blocks — so sparse files (Docker.raw and friends) are measured honestly.
    static func size(of paths: [String]) -> Int64 {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return 0 }
        var total: Int64 = 0
        // Chunk to stay well clear of ARG_MAX on large project trees.
        for chunk in stride(from: 0, to: existing.count, by: 200).map({
            Array(existing[$0..<min($0 + 200, existing.count)])
        }) {
            let out = Shell.run("/usr/bin/du", ["-sk", "--"] + chunk).out
            for line in out.split(separator: "\n") {
                if let kb = Int64(line.split(separator: "\t").first?
                    .trimmingCharacters(in: .whitespaces) ?? "") {
                    total += kb * 1024
                }
            }
        }
        return total
    }
}

func formatBytes(_ b: Int64) -> String {
    let gb = Double(b) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(b) / 1_048_576
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    return String(format: "%.0f KB", Double(b) / 1024)
}

// MARK: - Model

enum ItemKind {
    case cache          // regenerates on its own; safe, checked by default
    case buildArtifact  // rebuildable but costs you time; opt-in
    case blocked        // the app cannot do this — show the command instead
}

struct CleanupItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    let kind: ItemKind
    var bytes: Int64 = 0
    var selected: Bool
    /// Paths removed directly.
    var paths: [String] = []
    /// Keep the directory itself, delete what is inside (Trash, DeviceSupport).
    var contentsOnly: Bool = false
    /// Run instead of / in addition to path removal.
    var command: (tool: String, args: [String])? = nil
    /// Shown to the user when the app cannot perform the cleanup itself.
    var manualCommand: String? = nil
    /// Why it is blocked, in one line.
    var blockedReason: String? = nil
}

struct CleanupOutcome {
    let name: String
    let freed: Int64
    let failed: Bool
    let message: String?
    let manualCommand: String?
}

// MARK: - Safety

enum Guardrail {
    static let home = NSHomeDirectory()

    /// Directories we are willing to delete *inside*. Note the check below requires a
    /// path to be strictly deeper than one of these, so a bug can never remove a
    /// container itself (e.g. all of ~/Library/Caches).
    private static let containers = [
        "\(home)/Library/Caches",
        "\(home)/Library/Application Support",
        "\(home)/Library/Containers",
        "\(home)/Library/Developer",
        "\(home)/Library/Logs",
        "\(home)/Library/pnpm",
        "\(home)/.npm", "\(home)/.gradle", "\(home)/.cargo",
        "\(home)/.cache", "\(home)/.bun",
        "\(home)/Projects",
    ]

    /// Removable as a whole, and only ever with `contentsOnly` at the call site.
    private static let wholeDirAllowed = ["\(home)/.Trash"]

    static func isSafe(_ path: String) -> Bool {
        let p = (path as NSString).standardizingPath
        guard p.hasPrefix("/"), !p.contains(".."), p != "/", p != home else { return false }
        if wholeDirAllowed.contains(p) { return true }
        return containers.contains { p.hasPrefix($0 + "/") }
    }
}

// MARK: - Scanner

struct Scanner {
    let home = NSHomeDirectory()
    var progress: ((String, Double) -> Void)?

    func scan() -> [CleanupItem] {
        var items: [CleanupItem] = []
        let steps = 12.0
        var step = 0.0
        func tick(_ label: String) {
            step += 1
            progress?(label, step / steps)
        }

        // ---- Caches -------------------------------------------------------
        tick("Scanning application caches…")
        items.append(shipItCaches())

        tick("Scanning developer tool caches…")
        items.append(contentsOf: [
            simple(id: "npm", name: "npm / npx cache",
                   detail: "Package tarballs and cached npx installs",
                   paths: ["\(home)/.npm/_cacache", "\(home)/.npm/_npx", "\(home)/.npm/_logs"]),
            simple(id: "gradle", name: "Gradle caches",
                   detail: "Downloaded dependencies and stale daemon state",
                   paths: ["\(home)/.gradle/caches", "\(home)/.gradle/daemon"]),
            simple(id: "cargo", name: "Cargo registry cache",
                   detail: "Downloaded crate sources and archives",
                   paths: ["\(home)/.cargo/registry/cache", "\(home)/.cargo/registry/src"]),
            simple(id: "yarn", name: "Yarn / pnpm / bun caches",
                   detail: "Alternate package manager stores",
                   paths: ["\(home)/Library/Caches/Yarn", "\(home)/Library/pnpm/store",
                           "\(home)/.bun/install/cache"]),
            simple(id: "pip", name: "pip & Python caches",
                   detail: "Downloaded wheels",
                   paths: ["\(home)/Library/Caches/pip", "\(home)/.cache/pip"]),
            simple(id: "pods", name: "CocoaPods cache",
                   detail: "Cached pod specs and downloads",
                   paths: ["\(home)/Library/Caches/CocoaPods"]),
            simple(id: "playwright", name: "Playwright browsers",
                   detail: "Re-download with: npx playwright install",
                   paths: ["\(home)/Library/Caches/ms-playwright"]),
        ])

        tick("Scanning Homebrew…")
        items.append(simple(id: "brew", name: "Homebrew download cache",
                            detail: "Bottles and API metadata; brew re-fetches on demand",
                            paths: ["\(home)/Library/Caches/Homebrew/downloads",
                                    "\(home)/Library/Caches/Homebrew/api"]))

        tick("Scanning editor caches…")
        items.append(simple(id: "vscode", name: "VS Code caches",
                            detail: "Cache, CachedData and extension VSIXs — settings untouched",
                            paths: ["\(home)/Library/Application Support/Code/Cache",
                                    "\(home)/Library/Application Support/Code/CachedData",
                                    "\(home)/Library/Application Support/Code/CachedExtensionVSIXs",
                                    "\(home)/Library/Application Support/Code/GPUCache",
                                    "\(home)/Library/Application Support/Code/Service Worker"]))

        tick("Scanning Xcode…")
        items.append(simple(id: "derived", name: "Xcode DerivedData",
                            detail: "Rebuilt on next build",
                            paths: ["\(home)/Library/Developer/Xcode/DerivedData"],
                            contentsOnly: true))

        tick("Scanning simulators…")
        items.append(orphanedSimulators())

        tick("Scanning Trash…")
        items.append(trash())

        // ---- Build artifacts ----------------------------------------------
        tick("Scanning iOS device support…")
        items.append(simple(id: "devicesupport", name: "iOS DeviceSupport symbols",
                            detail: "Re-downloads next time you attach a device (a few minutes)",
                            paths: ["\(home)/Library/Developer/Xcode/iOS DeviceSupport"],
                            contentsOnly: true, kind: .buildArtifact))

        tick("Scanning Rust build output…")
        items.append(rustTargets())

        tick("Scanning node_modules…")
        items.append(nodeModules())

        tick("Scanning web build output…")
        items.append(webBuildOutput())

        // ---- Blocked -------------------------------------------------------
        items.append(contentsOf: blockedItems())

        return items.filter { $0.bytes > 1_048_576 || $0.kind == .blocked }
    }

    // MARK: builders

    private func simple(id: String, name: String, detail: String, paths: [String],
                        contentsOnly: Bool = false, kind: ItemKind = .cache) -> CleanupItem {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        return CleanupItem(id: id, name: name, detail: detail, kind: kind,
                           bytes: Sizer.size(of: existing),
                           selected: kind == .cache,
                           paths: existing, contentsOnly: contentsOnly)
    }

    private func shipItCaches() -> CleanupItem {
        let base = "\(home)/Library/Caches"
        let all = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
        let paths = all.filter { $0.hasSuffix(".ShipIt") || $0.hasSuffix("ShipIt") }
                       .map { "\(base)/\($0)" }
        return CleanupItem(id: "shipit", name: "App updater leftovers",
                           detail: "Downloaded installers from Squirrel/ShipIt auto-updates",
                           kind: .cache, bytes: Sizer.size(of: paths),
                           selected: true, paths: paths)
    }

    private func orphanedSimulators() -> CleanupItem {
        let devices = "\(home)/Library/Developer/CoreSimulator/Devices"
        let out = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices"]).out
        var orphans: [String] = []
        for line in out.split(separator: "\n") where line.contains("unavailable") {
            // Pull the UDID out of "Name (UDID) (Shutdown) (unavailable, …)"
            if let m = line.range(of: "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}",
                                  options: [.regularExpression, .caseInsensitive]) {
                orphans.append("\(devices)/\(line[m])")
            }
        }
        let existing = orphans.filter { FileManager.default.fileExists(atPath: $0) }
        return CleanupItem(
            id: "simorphan",
            name: "Orphaned simulators (\(existing.count))",
            detail: existing.isEmpty ? "None found"
                                     : "Devices whose iOS runtime is no longer installed",
            kind: .cache, bytes: Sizer.size(of: existing),
            selected: !existing.isEmpty, paths: [],
            command: existing.isEmpty ? nil : ("/usr/bin/xcrun", ["simctl", "delete", "unavailable"]))
    }

    private func trash() -> CleanupItem {
        let t = "\(home)/.Trash"
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: t)) ?? []
        let readable = !contents.isEmpty
        var item = simple(id: "trash", name: "Trash",
                          detail: readable ? "\(contents.count) item(s)"
                                           : "Empty, or needs Full Disk Access to read",
                          paths: [t], contentsOnly: true)
        if !readable {
            item.bytes = 0
            item.selected = false
        }
        return item
    }

    private func discover(named: String, under root: String, maxDepth: Int,
                          validate: (String) -> Bool) -> [String] {
        guard FileManager.default.fileExists(atPath: root) else { return [] }
        let out = Shell.run("/usr/bin/find",
                            [root, "-maxdepth", "\(maxDepth)", "-name", named,
                             "-type", "d", "-prune", "-print"]).out
        return out.split(separator: "\n").map(String.init).filter(validate)
    }

    private func rustTargets() -> CleanupItem {
        let root = "\(home)/Projects"
        // Only real Cargo target dirs — a sibling Cargo.toml is the proof.
        let dirs = discover(named: "target", under: root, maxDepth: 6) { path in
            let parent = (path as NSString).deletingLastPathComponent
            return FileManager.default.fileExists(atPath: "\(parent)/Cargo.toml")
        }
        // Keep expensive-to-refetch vendored caches (e.g. Tauri's CEF download).
        var subdirs: [String] = []
        for d in dirs {
            let kids = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
            subdirs += kids.filter { $0 == "debug" || $0 == "release" || $0.contains("-apple-") }
                           .map { "\(d)/\($0)" }
        }
        return CleanupItem(id: "rust", name: "Rust build output (\(dirs.count) crate(s))",
                           detail: "target/debug + release — next build is a full cold compile",
                           kind: .buildArtifact, bytes: Sizer.size(of: subdirs),
                           selected: false, paths: subdirs)
    }

    private func nodeModules() -> CleanupItem {
        let root = "\(home)/Projects"
        let locks = ["package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb"]
        // A lockfile is required: without one, reinstalling could resolve different versions.
        let dirs = discover(named: "node_modules", under: root, maxDepth: 6) { path in
            let parent = (path as NSString).deletingLastPathComponent
            guard !parent.contains("/node_modules/") else { return false }
            return locks.contains { FileManager.default.fileExists(atPath: "\(parent)/\($0)") }
        }
        return CleanupItem(id: "node", name: "node_modules (\(dirs.count) project(s))",
                           detail: "Only projects with a lockfile — reinstall with npm/yarn install",
                           kind: .buildArtifact, bytes: Sizer.size(of: dirs),
                           selected: false, paths: dirs)
    }

    private func webBuildOutput() -> CleanupItem {
        let root = "\(home)/Projects"
        var dirs: [String] = []
        for name in [".next", ".open-next", "dist", ".turbo", ".svelte-kit"] {
            dirs += discover(named: name, under: root, maxDepth: 5) { path in
                let parent = (path as NSString).deletingLastPathComponent
                guard !parent.contains("/node_modules/") else { return false }
                return FileManager.default.fileExists(atPath: "\(parent)/package.json")
            }
        }
        return CleanupItem(id: "web", name: "Web build output (\(dirs.count) dir(s))",
                           detail: ".next / .open-next / dist / .turbo — regenerated on next build",
                           kind: .buildArtifact, bytes: Sizer.size(of: dirs),
                           selected: false, paths: dirs)
    }

    private func blockedItems() -> [CleanupItem] {
        var out: [CleanupItem] = []
        let fm = FileManager.default

        let dyld = "/Library/Developer/CoreSimulator/Caches/dyld"
        if fm.fileExists(atPath: dyld) {
            let sip = Shell.run("/usr/bin/csrutil", ["status"]).out.contains("enabled")
            out.append(CleanupItem(
                id: "dyld", name: "Simulator dyld cache",
                detail: sip ? "SIP-protected — even sudo cannot remove this"
                            : "Requires sudo",
                kind: .blocked, bytes: Sizer.size(of: [dyld]), selected: false,
                manualCommand: "sudo rm -rf \(dyld)",
                blockedReason: sip
                    ? "System Integrity Protection is enabled. Removing this needs Recovery mode, and the cache rebuilds itself on the next simulator launch — usually not worth it."
                    : "Needs administrator rights."))
        }

        let docker = "\(home)/Library/Containers/com.docker.docker"
        if fm.fileExists(atPath: docker), !fm.fileExists(atPath: "/Applications/Docker.app") {
            out.append(CleanupItem(
                id: "docker", name: "Docker leftovers (app uninstalled)",
                detail: "Container data left behind after Docker was removed",
                kind: .blocked, bytes: Sizer.size(of: [docker]), selected: false,
                manualCommand: "rm -rf \"\(docker)\" \"\(home)/Library/Group Containers/group.com.docker\"",
                blockedReason: "macOS protects app containers (TCC). Grant your terminal Full Disk Access in System Settings → Privacy & Security, then run the command."))
        }

        let mysql = "/usr/local/mysql"
        if fm.fileExists(atPath: mysql) {
            out.append(CleanupItem(
                id: "mysql", name: "MySQL in /usr/local",
                detail: "Old manual MySQL install outside Homebrew",
                kind: .blocked, bytes: Sizer.size(of: [mysql]), selected: false,
                manualCommand: "sudo rm -rf /usr/local/mysql /usr/local/mysql-*",
                blockedReason: "Lives outside your home directory and needs administrator rights."))
        }

        return out.filter { $0.bytes > 0 }
    }
}

// MARK: - Cleaner

struct Cleaner {
    var progress: ((String, Double) -> Void)?

    func run(_ items: [CleanupItem]) -> [CleanupOutcome] {
        var outcomes: [CleanupOutcome] = []
        let total = Double(max(items.count, 1))

        for (i, item) in items.enumerated() {
            progress?("Cleaning \(item.name)…", Double(i) / total)

            let before = item.bytes
            var errors: [String] = []

            if let cmd = item.command {
                let r = Shell.run(cmd.tool, cmd.args, timeout: 300)
                if r.code != 0 { errors.append("exit \(r.code)") }
            }

            for path in item.paths {
                guard Guardrail.isSafe(path) else {
                    errors.append("refused unsafe path: \(path)")
                    continue
                }
                do {
                    if item.contentsOnly {
                        let kids = try FileManager.default.contentsOfDirectory(atPath: path)
                        for k in kids {
                            try? FileManager.default.removeItem(atPath: "\(path)/\(k)")
                        }
                    } else {
                        try FileManager.default.removeItem(atPath: path)
                    }
                } catch {
                    errors.append((error as NSError).localizedDescription)
                }
            }

            let after = Sizer.size(of: item.paths)
            let freed = max(0, before - after)
            outcomes.append(CleanupOutcome(
                name: item.name,
                freed: freed,
                failed: !errors.isEmpty && freed == 0,
                message: errors.first,
                manualCommand: errors.isEmpty ? nil : fallbackCommand(for: item)))
        }
        progress?("Done", 1.0)
        return outcomes
    }

    private func fallbackCommand(for item: CleanupItem) -> String {
        if let m = item.manualCommand { return m }
        let quoted = item.paths.map { "\"\($0)\"" }.joined(separator: " ")
        return item.contentsOnly ? "sudo rm -rf \(quoted)/*" : "sudo rm -rf \(quoted)"
    }
}

// MARK: - Disk

enum Disk {
    static func free() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(v?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

// MARK: - Status menu contents

/// Shared between the real NSMenu and `--menu`, so what gets verified on the
/// command line is the same structure the menu bar renders.
enum MenuRow: Equatable {
    case header(String)
    case line(String)
    case separator
    case action(String)
}

enum StatusMenu {
    static func rows(items: [CleanupItem], scanning: Bool, scanned: Bool) -> [MenuRow] {
        var rows: [MenuRow] = []

        if scanning {
            rows.append(.line("Scanning…"))
        } else if !scanned {
            rows.append(.line("Not scanned yet"))
        } else {
            let caches  = items.filter { $0.kind == .cache }
            let builds  = items.filter { $0.kind == .buildArtifact }
            let blocked = items.filter { $0.kind == .blocked }
            let total   = caches.reduce(0) { $0 + $1.bytes }

            rows.append(.line("Can recover: \(formatBytes(total))"))
            rows.append(.separator)

            for (group, title) in [(caches, "Caches"),
                                   (builds, "Build output (opt-in)"),
                                   (blocked, "Needs a command you run")] {
                guard !group.isEmpty else { continue }
                rows.append(.header(title))
                for i in group { rows.append(.line("\(i.name) — \(formatBytes(i.bytes))")) }
            }

            if caches.isEmpty && builds.isEmpty && blocked.isEmpty {
                rows.append(.line("Nothing worth cleaning"))
            }
        }

        rows.append(.separator)
        rows.append(.action("Open Clean Up My Machine"))
        rows.append(.action("Rescan"))
        rows.append(.separator)
        rows.append(.action("Quit"))
        return rows
    }
}
