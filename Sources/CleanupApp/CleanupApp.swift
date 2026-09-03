import SwiftUI

@main
struct CleanupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        SelfTest.runIfRequested()
        Headless.runIfRequested()
    }

    // The real window is built in AppDelegate so it can hide-on-close and keep a
    // fixed size; this scene exists only to satisfy the App protocol.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// `--scan` prints what the GUI would show, without touching anything.
/// Useful for verifying the engine and for scripting a dry run.
enum Headless {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard args.contains("--scan") else { return }

        var scanner = Scanner()
        if args.contains("--verbose") {
            scanner.progress = { label, p in
                FileHandle.standardError.write("[\(Int(p * 100))%] \(label)\n".data(using: .utf8)!)
            }
        }
        let items = scanner.scan().sorted { $0.bytes > $1.bytes }

        print("Free space: \(formatBytes(Disk.free()))\n")

        func section(_ title: String, _ kind: ItemKind) {
            let rows = items.filter { $0.kind == kind }
            guard !rows.isEmpty else { return }
            print(title)
            for i in rows {
                let mark = i.selected ? "[x]" : "[ ]"
                let name = i.name.count > 46 ? String(i.name.prefix(45)) + "…" : i.name
                let pad = String(repeating: " ", count: max(0, 46 - name.count))
                let size = formatBytes(i.bytes)
                let sizePad = String(repeating: " ", count: max(0, 9 - size.count))
                print("  \(mark) \(name)\(pad)\(sizePad)\(size)")
                if kind == .blocked, let c = i.manualCommand { print("        $ \(c)") }
            }
            let sum = rows.reduce(0) { $0 + $1.bytes }
            print("      subtotal: \(formatBytes(sum))\n")
        }

        section("CACHES (selected by default)", .cache)
        section("BUILD OUTPUT (opt-in)", .buildArtifact)
        section("BLOCKED — run these yourself", .blocked)

        let selected = items.filter { $0.selected && $0.kind != .blocked }
                            .reduce(0) { $0 + $1.bytes }
        print("Would recover with default selection: \(formatBytes(selected))")

        if args.contains("--menu") {
            print("\nMENU BAR:")
            for row in StatusMenu.rows(items: items, scanning: false, scanned: true) {
                switch row {
                case .separator:     print("  " + String(repeating: "-", count: 40))
                case .header(let t): print("  \(t.uppercased())")
                case .line(let t):   print("    \(t)")
                case .action(let t): print("  > \(t)")
                }
            }
        }
        exit(0)
    }
}

/// `--selftest` exercises the guardrail and the delete path against a throwaway
/// directory, so the destructive code is verified without risking real data.
enum SelfTest {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        var failures = 0
        func check(_ label: String, _ cond: Bool) {
            print("  \(cond ? "PASS" : "FAIL")  \(label)")
            if !cond { failures += 1 }
        }

        let home = NSHomeDirectory()
        print("Guardrail — must refuse:")
        check("/",                        !Guardrail.isSafe("/"))
        check("home itself",              !Guardrail.isSafe(home))
        check("~/Library/Caches (container)", !Guardrail.isSafe("\(home)/Library/Caches"))
        check("~/Projects (container)",   !Guardrail.isSafe("\(home)/Projects"))
        check("/etc/passwd",              !Guardrail.isSafe("/etc/passwd"))
        check("/System",                  !Guardrail.isSafe("/System"))
        check("~/Documents",              !Guardrail.isSafe("\(home)/Documents"))
        check("traversal escape",         !Guardrail.isSafe("\(home)/Projects/../../../etc"))
        check("relative path",            !Guardrail.isSafe("Projects/foo"))

        print("Guardrail — must allow:")
        check("~/Library/Caches/Foo",     Guardrail.isSafe("\(home)/Library/Caches/Foo"))
        check("~/Projects/a/node_modules", Guardrail.isSafe("\(home)/Projects/a/node_modules"))
        check("~/.npm/_cacache",          Guardrail.isSafe("\(home)/.npm/_cacache"))
        check("~/.Trash (contents only)", Guardrail.isSafe("\(home)/.Trash"))

        // Real delete against a scratch directory inside an allowed root.
        print("Delete path:")
        let scratch = "\(home)/Library/Caches/cleanup-selftest"
        let fm = FileManager.default
        try? fm.removeItem(atPath: scratch)
        try? fm.createDirectory(atPath: "\(scratch)/nested", withIntermediateDirectories: true)
        let blob = Data(repeating: 0x41, count: 3 * 1024 * 1024)
        fm.createFile(atPath: "\(scratch)/nested/blob.bin", contents: blob)

        let before = Sizer.size(of: [scratch])
        check("sized scratch dir (~3 MB)", before > 2_000_000)

        let item = CleanupItem(id: "selftest", name: "Self test", detail: "",
                               kind: .cache, bytes: before, selected: true, paths: [scratch])
        let outcomes = Cleaner().run([item])
        check("reported freed bytes", (outcomes.first?.freed ?? 0) > 2_000_000)
        check("directory removed",    !fm.fileExists(atPath: scratch))
        check("no error reported",    outcomes.first?.failed == false)

        // An item pointing somewhere forbidden must be refused, not deleted.
        let forbidden = CleanupItem(id: "bad", name: "Forbidden", detail: "",
                                    kind: .cache, bytes: 0, selected: true,
                                    paths: ["\(home)/Documents"])
        _ = Cleaner().run([forbidden])
        check("~/Documents untouched", fm.fileExists(atPath: "\(home)/Documents"))

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }
}

