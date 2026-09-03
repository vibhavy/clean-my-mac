#!/usr/bin/env swift
// Renders AppIcon.iconset — a Win95 window on a navy squircle with a clean check.
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func draw(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
    let s = size
    ctx.setAllowsAntialiasing(true)

    // Squircle background, navy gradient.
    let inset = s * 0.045
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22,
                      transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let colors = [NSColor(srgbRed: 0.13, green: 0.28, blue: 0.72, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.00, green: 0.00, blue: 0.42, alpha: 1).cgColor]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.restoreGState()

    // Win95 window glyph.
    let w = s * 0.52, h = s * 0.40
    let win = CGRect(x: (s - w) / 2, y: s * 0.34, width: w, height: h)
    ctx.setFillColor(NSColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1).cgColor)
    ctx.fill(win)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fill(CGRect(x: win.minX, y: win.minY, width: win.width, height: win.height * 0.72))
    // Title strip
    ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.10, blue: 0.55, alpha: 1).cgColor)
    ctx.fill(CGRect(x: win.minX, y: win.maxY - h * 0.22, width: w, height: h * 0.22))
    ctx.setStrokeColor(NSColor(white: 0.15, alpha: 1).cgColor)
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.stroke(win)

    // Content lines, dropped at tiny sizes where they would just smear.
    if s >= 64 {
        ctx.setFillColor(NSColor(white: 0.68, alpha: 1).cgColor)
        for i in 0..<3 {
            let y = win.maxY - h * (0.38 + Double(i) * 0.15)
            ctx.fill(CGRect(x: win.minX + w * 0.12, y: y,
                            width: w * (i == 2 ? 0.42 : 0.66), height: max(1, h * 0.055)))
        }
    }

    // Green check badge.
    let r = s * 0.20
    let c = CGPoint(x: s * 0.70, y: s * 0.32)
    ctx.setFillColor(NSColor(srgbRed: 0.16, green: 0.72, blue: 0.28, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(max(1.5, s * 0.035))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: c.x - r * 0.45, y: c.y + r * 0.02))
    ctx.addLine(to: CGPoint(x: c.x - r * 0.10, y: c.y - r * 0.35))
    ctx.addLine(to: CGPoint(x: c.x + r * 0.48, y: c.y + r * 0.38))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

func write(_ img: NSImage, _ name: String) {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

for (pt, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = CGFloat(pt * scale)
    let suffix = scale == 2 ? "@2x" : ""
    write(draw(px), "icon_\(pt)x\(pt)\(suffix).png")
}
print("iconset written to \(outDir)")
