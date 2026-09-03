import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        buildStatusItem()
        // Populate the menu bar without pulling the window off the idle screen.
        Model.shared.scan(visible: false)
    }

    /// Closing the window leaves the app running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Window

    private func buildWindow() {
        let content = NSHostingView(rootView: ContentView())
        content.frame = NSRect(x: 0, y: 0, width: 580, height: 510)
        // Without this, the title-bar safe area stacks on top of our own 28pt
        // navy bar and renders it double height.
        if #available(macOS 13.3, *) { content.safeAreaRegions = [] }

        window = NSWindow(
            contentRect: content.frame,
            // No .resizable — the window keeps this exact size.
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentView = content
        window.title = "Clean Up My Machine"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true   // our navy bar shows through
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Win.face)
        window.appearance = NSAppearance(named: .aqua)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CleanupMainWindow")

        if let dest = ProcessInfo.processInfo.environment["CLEANUP_WINDOW_ID_FILE"] {
            try? "\(window.windowNumber)".write(toFile: dest, atomically: true, encoding: .utf8)
        }
        showWindow()
    }

    /// Hide instead of destroy, so the menu bar can bring it back.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        window.orderOut(nil)
        return false
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "internaldrive",
                                          accessibilityDescription: "Clean Up My Machine")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Rebuilt on every open, so it always reflects the latest scan.
    /// Row structure comes from StatusMenu, the same builder `--menu` prints.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let m = Model.shared
        for row in StatusMenu.rows(items: m.items, scanning: m.scanning, scanned: m.scanned) {
            switch row {
            case .separator:
                menu.addItem(.separator())
            case .header(let t):
                menu.addItem(sectionHeader(t))
            case .line(let t):
                let mi = item(t, #selector(openApp), key: "")
                if t.contains(" — ") { mi.indentationLevel = 1 }
                menu.addItem(mi)
            case .action(let t):
                let sel: Selector = t == "Rescan" ? #selector(rescan)
                                  : t == "Quit"   ? #selector(quit)
                                                  : #selector(openApp)
                let key = t == "Quit" ? "q" : (t == "Rescan" ? "r" : "o")
                menu.addItem(item(t, sel, key: key))
            }
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        mi.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
        return mi
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mi.isEnabled = false
        mi.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                         .foregroundColor: NSColor.secondaryLabelColor])
        return mi
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func openApp() {
        if Model.shared.scanned, Model.shared.phase == .idle {
            Model.shared.phase = .review
        }
        showWindow()
    }

    @objc private func rescan() {
        Model.shared.scan(visible: Model.shared.phase != .idle)
        showWindow()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
