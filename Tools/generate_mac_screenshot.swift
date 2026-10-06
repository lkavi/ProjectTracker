// Places a captured Mac window (screencapture -o -l <id>) on the store
// background at the Mac App Store size, 2880 × 1800.
//
//   swift Tools/generate_mac_screenshot.swift <window.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let window = NSImage(contentsOfFile: args[1]) else {
    print("usage: generate_mac_screenshot.swift <window.png> <out.png>")
    exit(1)
}

let W: CGFloat = 2880, H: CGFloat = 1800
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Same blue as the app icon and the product-page header.
func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
NSGradient(starting: rgb(76, 111, 255), ending: rgb(36, 52, 170))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

// The window, as large as fits with a margin, centred, with a soft shadow.
let margin: CGFloat = 120
let size = window.size
let scale = min((W - 2 * margin) / size.width, (H - 2 * margin) / size.height)
let rect = NSRect(x: (W - size.width * scale) / 2, y: (H - size.height * scale) / 2,
                  width: size.width * scale, height: size.height * scale)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.shadowBlurRadius = 80
shadow.shadowOffset = NSSize(width: 0, height: -30)
shadow.set()
window.draw(in: rect)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
