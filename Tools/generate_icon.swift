#!/usr/bin/swift

import AppKit
import CoreGraphics

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size

    // ── Background gradient (dark slate)
    let bgColors = [
        CGColor(red: 0.09, green: 0.10, blue: 0.13, alpha: 1),
        CGColor(red: 0.14, green: 0.16, blue: 0.21, alpha: 1)
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // ── Subtle inner glow ring
    let glowColors = [
        CGColor(red: 0.18, green: 0.72, blue: 0.45, alpha: 0.10),
        CGColor(red: 0.18, green: 0.72, blue: 0.45, alpha: 0.0)
    ] as CFArray
    let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(glowGrad,
        startCenter: CGPoint(x: s * 0.5, y: s * 0.55), startRadius: 0,
        endCenter: CGPoint(x: s * 0.5, y: s * 0.55), endRadius: s * 0.5,
        options: [])

    // ── Graduation cap — board (diamond)
    let cx = s * 0.5
    let cy = s * 0.54

    // Diamond board
    let hw = s * 0.34   // half-width
    let hh = s * 0.13   // half-height

    let boardPath = CGMutablePath()
    boardPath.move(to: CGPoint(x: cx,      y: cy + hh))
    boardPath.addLine(to: CGPoint(x: cx + hw, y: cy))
    boardPath.addLine(to: CGPoint(x: cx,      y: cy - hh))
    boardPath.addLine(to: CGPoint(x: cx - hw, y: cy))
    boardPath.closeSubpath()

    // Board fill: green gradient
    let boardColors = [
        CGColor(red: 0.22, green: 0.85, blue: 0.52, alpha: 1),
        CGColor(red: 0.08, green: 0.58, blue: 0.36, alpha: 1)
    ] as CFArray
    let boardGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: boardColors, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(boardPath)
    ctx.clip()
    ctx.drawLinearGradient(boardGrad,
        start: CGPoint(x: cx - hw, y: cy + hh),
        end: CGPoint(x: cx + hw, y: cy - hh), options: [])
    ctx.restoreGState()

    // Board edge highlight (top face lighter)
    let topFace = CGMutablePath()
    topFace.move(to: CGPoint(x: cx,      y: cy + hh))
    topFace.addLine(to: CGPoint(x: cx + hw, y: cy))
    topFace.addLine(to: CGPoint(x: cx,      y: cy + hh * 0.35))
    topFace.addLine(to: CGPoint(x: cx - hw, y: cy))
    topFace.closeSubpath()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.addPath(topFace)
    ctx.fillPath()

    // ── Cap dome / cylinder below board
    let domeW = s * 0.28
    let domeH = s * 0.17
    let domeX = cx - domeW / 2
    let domeY = cy - hh - domeH * 0.85

    let domeRect = CGRect(x: domeX, y: domeY, width: domeW, height: domeH)
    let domeColors = [
        CGColor(red: 0.12, green: 0.62, blue: 0.40, alpha: 1),
        CGColor(red: 0.06, green: 0.40, blue: 0.26, alpha: 1)
    ] as CFArray
    let domeGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: domeColors, locations: [0, 1])!

    // Trapezoid dome
    let domePath = CGMutablePath()
    domePath.move(to: CGPoint(x: cx - domeW * 0.42, y: domeY + domeH))
    domePath.addLine(to: CGPoint(x: cx + domeW * 0.42, y: domeY + domeH))
    domePath.addLine(to: CGPoint(x: cx + domeW * 0.5,  y: domeY))
    domePath.addLine(to: CGPoint(x: cx - domeW * 0.5,  y: domeY))
    domePath.closeSubpath()
    ctx.saveGState()
    ctx.addPath(domePath)
    ctx.clip()
    ctx.drawLinearGradient(domeGrad,
        start: CGPoint(x: 0, y: domeY + domeH),
        end: CGPoint(x: 0, y: domeY), options: [])
    ctx.restoreGState()

    // ── Tassel string (right side)
    let tasselX = cx + hw
    let tasselTopY = cy
    let tasselBottomY = cy - hh * 2.6
    ctx.setStrokeColor(CGColor(red: 0.22, green: 0.85, blue: 0.52, alpha: 0.85))
    ctx.setLineWidth(s * 0.018)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: tasselX, y: tasselTopY))
    ctx.addLine(to: CGPoint(x: tasselX + s * 0.04, y: tasselBottomY + s * 0.04))
    ctx.strokePath()
    // Tassel ball
    ctx.setFillColor(CGColor(red: 0.22, green: 0.85, blue: 0.52, alpha: 1))
    let tasselR = s * 0.03
    ctx.fillEllipse(in: CGRect(x: tasselX + s * 0.04 - tasselR,
                               y: tasselBottomY,
                               width: tasselR * 2, height: tasselR * 2))

    // ── Progress bar at bottom (3 segments with fill)
    let barY = s * 0.17
    let barH = s * 0.058
    let barW = s * 0.68
    let barX = (s - barW) / 2
    let corner = barH / 2

    // Track
    let trackPath = CGPath(roundedRect: CGRect(x: barX, y: barY, width: barW, height: barH),
                            cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
    ctx.addPath(trackPath)
    ctx.fillPath()

    // Fill ~72%
    let fillFrac: CGFloat = 0.72
    let fillW = barW * fillFrac
    let fillColors = [
        CGColor(red: 0.22, green: 0.85, blue: 0.52, alpha: 1),
        CGColor(red: 0.10, green: 0.65, blue: 0.80, alpha: 1)
    ] as CFArray
    let fillGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: fillColors, locations: [0, 1])!
    let fillPath = CGPath(roundedRect: CGRect(x: barX, y: barY, width: fillW, height: barH),
                           cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.saveGState()
    ctx.addPath(fillPath)
    ctx.clip()
    ctx.drawLinearGradient(fillGrad,
        start: CGPoint(x: barX, y: 0), end: CGPoint(x: barX + fillW, y: 0), options: [])
    ctx.restoreGState()

    // ── Tick marks / stage dividers on bar
    let stages = 7
    for i in 1..<stages {
        let tx = barX + barW * CGFloat(i) / CGFloat(stages)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.22))
        ctx.setLineWidth(s * 0.008)
        ctx.move(to: CGPoint(x: tx, y: barY))
        ctx.addLine(to: CGPoint(x: tx, y: barY + barH))
        ctx.strokePath()
    }

    image.unlockFocus()
    return image
}

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

struct IconSpec {
    let name: String
    let size: Int
}

let specs: [IconSpec] = [
    IconSpec(name: "icon_16x16",      size: 16),
    IconSpec(name: "icon_16x16@2x",   size: 32),
    IconSpec(name: "icon_32x32",      size: 32),
    IconSpec(name: "icon_32x32@2x",   size: 64),
    IconSpec(name: "icon_128x128",    size: 128),
    IconSpec(name: "icon_128x128@2x", size: 256),
    IconSpec(name: "icon_256x256",    size: 256),
    IconSpec(name: "icon_256x256@2x", size: 512),
    IconSpec(name: "icon_512x512",    size: 512),
    IconSpec(name: "icon_512x512@2x", size: 1024),
]

for spec in specs {
    let img = drawIcon(size: CGFloat(spec.size))
    guard let tiff = img.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: could not render \(spec.name)")
        continue
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(spec.name).png")
    do {
        try png.write(to: url)
        print("✓ \(spec.name).png  (\(spec.size)x\(spec.size))")
    } catch {
        print("ERROR writing \(spec.name): \(error)")
    }
}
