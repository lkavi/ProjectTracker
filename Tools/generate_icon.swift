#!/usr/bin/swift
// Renders the app icon set.
//   swift Tools/generate_icon.swift <output-dir> [milestones|steps]
// Writes ios-1024.png (full-bleed, iOS masks it) and the macOS set with the
// rounded-square shape and transparent margin baked in, plus preview-*.png.
import AppKit

enum Style: String { case milestones, steps }

struct Palette { let top: CGColor; let bottom: CGColor; let accent: CGColor }

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

func palette(_ style: Style) -> Palette {
    switch style {
    case .milestones: return Palette(top: rgb(76, 111, 255), bottom: rgb(43, 63, 203), accent: rgb(255, 194, 75))
    case .steps:      return Palette(top: rgb(20, 184, 166), bottom: rgb(15, 118, 110), accent: rgb(255, 255, 255))
    }
}

func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect {
    CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
}

/// Vertical timeline: a finished node with a check, the current node with an
/// accent dot, an upcoming hollow node, and a short label bar beside each.
func drawMilestones(_ ctx: CGContext, in r: CGRect, _ p: Palette) {
    let s = r.width
    let x = r.minX + s * 0.34
    let ys = [r.minY + s * 0.735, r.minY + s * 0.50, r.minY + s * 0.265]   // top, middle, bottom
    let nodeR = s * 0.082
    let lw = s * 0.034
    let white = CGColor(gray: 1, alpha: 1)

    ctx.setLineCap(.round); ctx.setLineJoin(.round)

    // connector
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45)); ctx.setLineWidth(lw)
    ctx.move(to: CGPoint(x: x, y: ys[0])); ctx.addLine(to: CGPoint(x: x, y: ys[2])); ctx.strokePath()

    // label bars
    let barX = x + nodeR + s * 0.09
    let barH = s * 0.052
    let widths: [CGFloat] = [s * 0.30, s * 0.36, s * 0.24]
    let alphas: [CGFloat] = [0.45, 0.95, 0.55]
    for i in 0..<3 {
        ctx.setFillColor(CGColor(gray: 1, alpha: alphas[i]))
        let bar = CGRect(x: barX, y: ys[i] - barH / 2, width: widths[i], height: barH)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.fillPath()
    }

    // done: filled disc with a check in the background colour
    ctx.setFillColor(white); ctx.fillEllipse(in: circle(x, ys[0], nodeR))
    ctx.setStrokeColor(p.bottom); ctx.setLineWidth(lw * 0.95)
    ctx.move(to: CGPoint(x: x - nodeR * 0.48, y: ys[0] + nodeR * 0.02))
    ctx.addLine(to: CGPoint(x: x - nodeR * 0.10, y: ys[0] - nodeR * 0.36))
    ctx.addLine(to: CGPoint(x: x + nodeR * 0.52, y: ys[0] + nodeR * 0.40))
    ctx.strokePath()

    // current: ring with an accent dot
    ctx.setStrokeColor(white); ctx.setLineWidth(lw)
    ctx.strokeEllipse(in: circle(x, ys[1], nodeR - lw / 2))
    ctx.setFillColor(p.accent); ctx.fillEllipse(in: circle(x, ys[1], nodeR * 0.42))

    // upcoming: hollow ring
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85)); ctx.setLineWidth(lw)
    ctx.strokeEllipse(in: circle(x, ys[2], nodeR - lw / 2))
}

/// Three ascending steps with a check on the top one.
func drawSteps(_ ctx: CGContext, in r: CGRect, _ p: Palette) {
    let s = r.width
    let w = s * 0.20, gap = s * 0.035, base = r.minY + s * 0.24
    let heights: [CGFloat] = [s * 0.16, s * 0.30, s * 0.46]
    let x0 = r.minX + (s - (3 * w + 2 * gap)) / 2
    let corner = s * 0.035
    for i in 0..<3 {
        let rect = CGRect(x: x0 + CGFloat(i) * (w + gap), y: base, width: w, height: heights[i])
        ctx.setFillColor(CGColor(gray: 1, alpha: i == 2 ? 1.0 : 0.55 + 0.15 * CGFloat(i)))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.fillPath()
    }
    // check on the top step
    let cx = x0 + 2 * (w + gap) + w / 2, cy = base + heights[2] - s * 0.10
    ctx.setStrokeColor(p.bottom); ctx.setLineWidth(s * 0.032); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: cx - s * 0.055, y: cy))
    ctx.addLine(to: CGPoint(x: cx - s * 0.012, y: cy - s * 0.045))
    ctx.addLine(to: CGPoint(x: cx + s * 0.06, y: cy + s * 0.05))
    ctx.strokePath()
}

func render(pixels: Int, mac: Bool, style: Style) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    let size = CGFloat(pixels)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let shape = mac ? full.insetBy(dx: size * 0.098, dy: size * 0.098) : full
    let radius = mac ? shape.width * 0.225 : 0
    let path = CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let p = palette(style)

    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [p.top, p.bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: shape.midX, y: shape.maxY),
                           end: CGPoint(x: shape.midX, y: shape.minY), options: [])
    switch style {
    case .milestones: drawMilestones(ctx, in: shape, p)
    case .steps:      drawSteps(ctx, in: shape, p)
    }
    ctx.restoreGState()

    if mac {   // faint edge so the shape reads on light and dark docks
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10))
        ctx.setLineWidth(max(1, size * 0.004))
        ctx.strokePath()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
let style = Style(rawValue: args.count > 2 ? args[2] : "milestones") ?? .milestones
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func write(_ name: String, _ data: Data) {
    try! data.write(to: outDir.appendingPathComponent(name))
    print("✓ \(name)")
}

write("ios-1024.png", render(pixels: 1024, mac: false, style: style))
let macSlots: [(String, Int)] = [("mac-16", 16), ("mac-16@2x", 32), ("mac-32", 32), ("mac-32@2x", 64),
                                 ("mac-128", 128), ("mac-128@2x", 256), ("mac-256", 256), ("mac-256@2x", 512),
                                 ("mac-512", 512), ("mac-512@2x", 1024)]
for (name, px) in macSlots { write("\(name).png", render(pixels: px, mac: true, style: style)) }
write("preview-\(style.rawValue).png", render(pixels: 512, mac: true, style: style))
