import SwiftUI
import AppKit

enum Phase { case idle, scanning, review, cleaning, done }

@MainActor final class Model: ObservableObject {
    static let shared = Model()

    @Published var phase: Phase = .idle
    @Published var items: [CleanupItem] = []
    @Published var outcomes: [CleanupOutcome] = []
    @Published var status = ""
    @Published var progress = 0.0
    @Published var freeBefore: Int64 = Disk.free()
    @Published var freeAfter: Int64 = 0
    @Published var scanning = false
    @Published var scanned = false

    var reclaimable: Int64 {
        items.filter { $0.selected && $0.kind != .blocked }.reduce(0) { $0 + $1.bytes }
    }
    var blocked: [CleanupItem] { items.filter { $0.kind == .blocked } }
    var actionable: [CleanupItem] { items.filter { $0.kind != .blocked } }

    /// `visible` drives the progress screen. A background scan at launch keeps the
    /// menu bar populated without yanking the window off the idle screen.
    func scan(visible: Bool = true) {
        guard !scanning else { if visible { phase = .scanning }; return }
        scanning = true
        scanned = false
        progress = 0
        status = "Starting…"
        freeBefore = Disk.free()
        if visible { phase = .scanning }
        Task.detached(priority: .userInitiated) {
            var scanner = Scanner()
            scanner.progress = { label, p in
                Task { @MainActor in self.status = label; self.progress = p }
            }
            let found = scanner.scan()
            await MainActor.run {
                self.items = found.sorted { $0.bytes > $1.bytes }
                self.scanning = false
                self.scanned = true
                if self.phase == .scanning { self.phase = .review }
            }
        }
    }

    /// Idle screen button: skip straight to review if the background scan already finished.
    func requestReview() {
        if scanned { phase = .review } else { scan(visible: true) }
    }

    func clean() {
        let todo = items.filter { $0.selected && $0.kind != .blocked }
        guard !todo.isEmpty else { return }
        phase = .cleaning
        progress = 0
        Task.detached(priority: .userInitiated) {
            var cleaner = Cleaner()
            cleaner.progress = { label, p in
                Task { @MainActor in self.status = label; self.progress = p }
            }
            let results = cleaner.run(todo)
            await MainActor.run {
                self.outcomes = results
                self.freeAfter = Disk.free()
                self.phase = .done
            }
        }
    }

    func reset() {
        phase = .idle
        outcomes = []
        progress = 0
        freeBefore = Disk.free()
    }

    var reclaimableAll: Int64 {
        items.filter { $0.kind == .cache }.reduce(0) { $0 + $1.bytes }
    }
}

struct ContentView: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title: "Clean Up My Machine")
            VStack(spacing: 0) {
                switch model.phase {
                case .idle:     IdleView(model: model)
                case .scanning: BusyView(model: model, verb: "Scanning")
                case .review:   ReviewView(model: model)
                case .cleaning: BusyView(model: model, verb: "Cleaning")
                case .done:     ResultView(model: model)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .foregroundColor(Win.text)
        .frame(width: 580, height: 510)
        .background(Win.face)
        .preferredColorScheme(.light)
    }
}

// MARK: - Idle

struct IdleView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "internaldrive")
                .font(.system(size: 44)).foregroundColor(Win.titleBar)
            Text("Clean Up My Machine")
                .font(Win.font(15, bold: true))
            Text("Finds caches and build output that can be safely removed,\nshows you the total, and asks before deleting anything.")
                .font(Win.font(11))
                .multilineTextAlignment(.center)
                .foregroundColor(Win.text.opacity(0.75))
            HStack(spacing: 6) {
                Text("Free space now:").font(Win.font(11))
                Text(formatBytes(model.freeBefore)).font(Win.font(11, bold: true))
            }
            .padding(.top, 2)
            Text(model.scanning ? "Checking what can be recovered…"
                                : (model.scanned ? "Found \(formatBytes(model.reclaimableAll)) of caches"
                                                 : " "))
                .font(Win.font(10))
                .foregroundColor(Win.text.opacity(0.6))
            Spacer()
            RetroButton(title: model.scanned ? "Review \(formatBytes(model.reclaimableAll))"
                                             : "Recover Storage",
                        wide: true, defaulted: true) { model.requestReview() }
            Spacer().frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Busy

struct BusyView: View {
    @ObservedObject var model: Model
    let verb: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("\(verb)…").font(Win.font(13, bold: true))
            Text(model.status)
                .font(Win.font(11))
                .foregroundColor(Win.text.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
            RetroProgress(value: model.progress).frame(width: 340)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Review

struct ReviewView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Can recover:").font(Win.font(12))
                Text(formatBytes(model.reclaimable)).font(Win.font(17, bold: true))
                Spacer()
                Text("\(formatBytes(model.freeBefore)) free now")
                    .font(Win.font(10)).foregroundColor(Win.text.opacity(0.7))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("Caches — safe, these rebuild themselves")
                    ForEach(rows(.cache)) { row(for: $0) }

                    if !rows(.buildArtifact).isEmpty {
                        SectionHeader("Build output — rebuildable, but costs you time")
                        ForEach(rows(.buildArtifact)) { row(for: $0) }
                    }
                }
                .padding(6)
            }
            .sunkenField()

            if !model.blocked.isEmpty {
                Text("\(model.blocked.count) item(s) need a command you run yourself — shown after cleanup.")
                    .font(Win.font(10)).foregroundColor(Win.text.opacity(0.7))
            }

            HStack {
                RetroButton(title: "Back") { model.reset() }
                Spacer()
                RetroButton(title: "Clean \(formatBytes(model.reclaimable))",
                            wide: true, enabled: model.reclaimable > 0, defaulted: true) {
                    model.clean()
                }
            }
        }
    }

    private func rows(_ kind: ItemKind) -> [CleanupItem] {
        model.items.filter { $0.kind == kind }
    }

    private func row(for item: CleanupItem) -> some View {
        let idx = model.items.firstIndex { $0.id == item.id }!
        return HStack(alignment: .top, spacing: 8) {
            RetroCheckbox(checked: Binding(
                get: { model.items[idx].selected },
                set: { model.items[idx].selected = $0 }))
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(Win.font(11))
                Text(item.detail).font(Win.font(10))
                    .foregroundColor(Win.text.opacity(0.6))
            }
            Spacer(minLength: 8)
            Text(formatBytes(item.bytes))
                .font(Win.mono(10))
                .foregroundColor(Win.text)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.items[idx].selected.toggle() }
    }
}

struct SectionHeader: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text.uppercased())
            .font(Win.font(9, bold: true))
            .foregroundColor(Win.text.opacity(0.55))
            .padding(.top, 8).padding(.bottom, 3).padding(.horizontal, 4)
    }
}

// MARK: - Result

struct ResultView: View {
    @ObservedObject var model: Model

    private var freed: Int64 { model.outcomes.reduce(0) { $0 + $1.freed } }
    private var manual: [(String, String, String?)] {
        var out: [(String, String, String?)] = []
        for o in model.outcomes where o.manualCommand != nil {
            out.append((o.name, o.manualCommand!, o.message))
        }
        for b in model.blocked {
            out.append((b.name + " (\(formatBytes(b.bytes)))", b.manualCommand ?? "", b.blockedReason))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22)).foregroundColor(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Recovered \(formatBytes(freed))").font(Win.font(14, bold: true))
                    Text("\(formatBytes(model.freeBefore)) free → \(formatBytes(model.freeAfter)) free")
                        .font(Win.font(10)).foregroundColor(Win.text.opacity(0.7))
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.outcomes.enumerated()), id: \.offset) { _, o in
                        HStack {
                            Text(o.failed ? "✕" : "✓")
                                .font(Win.mono(10))
                                .foregroundColor(o.failed ? .red : .green)
                            Text(o.name).font(Win.font(11))
                            Spacer()
                            Text(formatBytes(o.freed)).font(Win.mono(10))
                        }
                    }

                    if !manual.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("RUN THESE YOURSELF")
                            .font(Win.font(9, bold: true))
                            .foregroundColor(Win.text.opacity(0.55))
                        ForEach(Array(manual.enumerated()), id: \.offset) { _, m in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.0).font(Win.font(11, bold: true))
                                if let why = m.2, !why.isEmpty {
                                    Text(why).font(Win.font(10))
                                        .foregroundColor(Win.text.opacity(0.65))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Text(m.1)
                                        .font(Win.mono(10))
                                        .textSelection(.enabled)
                                        .padding(5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black)
                                        .foregroundColor(.green)
                                        .overlay(Bevel(raised: false))
                                    CopyButton(text: m.1)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                }
                .padding(8)
            }
            .sunkenField()

            HStack {
                RetroButton(title: "Scan Again") { model.reset(); model.scan(visible: true) }
                Spacer()
                RetroButton(title: "Close", defaulted: true) { NSApp.terminate(nil) }
            }
        }
    }
}

struct CopyButton: View {
    let text: String
    @State private var copied = false
    var body: some View {
        RetroButton(title: copied ? "Copied" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        }
    }
}
