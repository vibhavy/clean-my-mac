import SwiftUI
import AppKit

// MARK: - Palette

enum Win {
    static let face        = Color(red: 192/255, green: 192/255, blue: 192/255)
    static let light       = Color(red: 223/255, green: 223/255, blue: 223/255)
    static let highlight   = Color.white
    static let shadow      = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let darkShadow  = Color(red:  10/255, green:  10/255, blue:  10/255)
    static let titleBar    = Color(red:   0/255, green:   0/255, blue: 128/255)
    static let titleBar2   = Color(red:  16/255, green:  52/255, blue: 166/255)
    static let field       = Color.white
    static let text        = Color.black
    static let disabled    = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let desktop     = Color(red: 214/255, green: 232/255, blue: 213/255)
    static let selection   = Color(red:   0/255, green:   0/255, blue: 128/255)

    /// Tahoma is the authentic Win95 UI face and ships with macOS.
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        let name = bold ? "Tahoma Bold" : "Tahoma"
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: bold ? .bold : .regular)
    }
    static func mono(_ size: CGFloat) -> Font {
        NSFont(name: "Monaco", size: size) != nil ? .custom("Monaco", size: size)
                                                  : .system(size: size, design: .monospaced)
    }
}

// MARK: - Bevel

/// The 2px Win95 border. `raised` for buttons/panels, `sunken` for fields and wells.
struct Bevel: View {
    var raised: Bool = true
    var thin: Bool = false

    var body: some View {
        let outerTL = raised ? Win.highlight : Win.shadow
        let outerBR = raised ? Win.darkShadow : Win.highlight
        let innerTL = raised ? Win.light : Win.darkShadow
        let innerBR = raised ? Win.shadow : Win.light

        ZStack {
            BevelFrame(topLeft: outerTL, bottomRight: outerBR)
            if !thin {
                BevelFrame(topLeft: innerTL, bottomRight: innerBR).padding(1)
            }
        }
    }
}

private struct BevelFrame: View {
    let topLeft: Color
    let bottomRight: Color
    var body: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
            }.stroke(topLeft, lineWidth: 1)
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
            }.stroke(bottomRight, lineWidth: 1)
        }
    }
}

extension View {
    func bevel(raised: Bool = true, thin: Bool = false) -> some View {
        background(Win.face).overlay(Bevel(raised: raised, thin: thin))
    }
    func sunkenField() -> some View {
        background(Win.field).overlay(Bevel(raised: false))
    }
}

// MARK: - Button

struct RetroButton: View {
    let title: String
    var wide: Bool = false
    var enabled: Bool = true
    var defaulted: Bool = false
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(Win.font(11))
            .foregroundColor(enabled ? Win.text : Win.disabled)
            .frame(minWidth: wide ? 150 : 75)
            .frame(height: 23)
            .padding(.horizontal, 10)
            .background(Win.face)
            .overlay(Bevel(raised: !pressed))
            .overlay(
                Rectangle()
                    .stroke(Win.darkShadow, lineWidth: defaulted ? 1 : 0)
                    .padding(-2)
            )
            .offset(x: pressed ? 1 : 0, y: pressed ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if enabled { pressed = true } }
                    .onEnded { _ in pressed = false }
            )
            .opacity(enabled ? 1 : 0.7)
    }
}

// MARK: - Checkbox

struct RetroCheckbox: View {
    @Binding var checked: Bool
    var enabled: Bool = true

    var body: some View {
        ZStack {
            Rectangle().fill(enabled ? Win.field : Win.face)
                .frame(width: 13, height: 13)
                .overlay(Bevel(raised: false))
            if checked {
                Path { p in
                    p.move(to: CGPoint(x: 2.5, y: 6.5)); p.addLine(to: CGPoint(x: 5, y: 9))
                    p.addLine(to: CGPoint(x: 10.5, y: 3))
                }
                .stroke(enabled ? Win.text : Win.disabled,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 13, height: 13)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if enabled { checked.toggle() } }
    }
}

// MARK: - Title bar

/// Retro navy bar, but the window controls are the real macOS traffic lights
/// sitting at their default position — we just leave room for them on the left.
struct TitleBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 74)   // clearance for the traffic lights
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.trailing, 5)
            Text(title)
                .font(Win.font(11, bold: true))
                .foregroundColor(.white)
            Spacer(minLength: 8)
        }
        .frame(height: 28)
        .background(
            LinearGradient(colors: [Win.titleBar, Win.titleBar2],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}

// MARK: - Group box

struct GroupBox95<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .padding(10)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    ZStack {
                        BevelFrame(topLeft: Win.shadow, bottomRight: Win.highlight)
                        BevelFrame(topLeft: Win.highlight, bottomRight: Win.shadow).padding(1)
                    }
                )
            Text(title)
                .font(Win.font(11))
                .foregroundColor(Win.text)
                .padding(.horizontal, 4)
                .background(Win.face)
                .offset(x: 8, y: -6)
        }
    }
}

// MARK: - Segmented progress bar

struct RetroProgress: View {
    var value: Double   // 0...1

    var body: some View {
        GeometryReader { geo in
            let blockW: CGFloat = 9, gap: CGFloat = 2
            let total = Int((geo.size.width - 4) / (blockW + gap))
            let filled = Int((Double(total) * max(0, min(1, value))).rounded())
            HStack(spacing: gap) {
                ForEach(0..<max(total, 0), id: \.self) { i in
                    Rectangle()
                        .fill(i < filled ? Win.titleBar : Color.clear)
                        .frame(width: blockW)
                }
                Spacer(minLength: 0)
            }
            .padding(2)
        }
        .frame(height: 20)
        .background(Win.face)
        .overlay(Bevel(raised: false))
    }
}
