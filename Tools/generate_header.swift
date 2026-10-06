// Renders the App Store product-page header (5244 × 2950) from two app
// screenshots: the icon and headline on the left, phones on the right.
// Key content stays inside the middle band so the wide 3840 × 1646 crop
// keeps it.
//
//   swift Tools/generate_header.swift <icon.png> <left-screen.png> <right-screen.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else {
    print("usage: generate_header.swift <icon.png> <left-screen.png> <right-screen.png> <out.png>")
    exit(1)
}

let W: CGFloat = 5244, H: CGFloat = 2950

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

func image(_ path: String) -> NSImage {
    guard let img = NSImage(contentsOfFile: path) else { print("can't read \(path)"); exit(1) }
    return img
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: the icon's blue, lighter at the top left.
NSGradient(starting: rgb(76, 111, 255), ending: rgb(36, 52, 170))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

// A soft light behind the phones.
NSGradient(colors: [NSColor(white: 1, alpha: 0.16), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 2500, y: 200, width: 2700, height: 2550)), relativeCenterPosition: .zero)

// MARK: Left: icon, name, headline

let left: CGFloat = 400
let icon = image(args[1])
let iconSize: CGFloat = 400
let iconRect = NSRect(x: left, y: 1900, width: iconSize, height: iconSize)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: iconRect, xRadius: iconSize * 0.225, yRadius: iconSize * 0.225).addClip()
icon.draw(in: iconRect)
NSGraphicsContext.restoreGraphicsState()

/// Draws text with its top edge at `point.y` and returns its height.
@discardableResult
func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight,
          color: NSColor, width: CGFloat = 2200, lineSpacing: CGFloat = 0) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = lineSpacing
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: style,
        .kern: -size * 0.01,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let bounds = s.boundingRect(with: NSSize(width: width, height: 2000), options: [.usesLineFragmentOrigin])
    s.draw(with: NSRect(x: point.x, y: point.y - bounds.height, width: width, height: bounds.height),
           options: [.usesLineFragmentOrigin])
    return bounds.height
}

draw("Project Tracker", at: NSPoint(x: left + iconSize + 70, y: 2190), size: 150, weight: .semibold,
     color: NSColor(white: 1, alpha: 0.9))
var y: CGFloat = 1760
y -= draw("Paste your deadlines.\nGet the whole plan.", at: NSPoint(x: left, y: y), size: 215, weight: .bold,
          color: .white, width: 2250, lineSpacing: 6)
y -= 90
draw("Apple Intelligence turns your course email into stages, dates and tasks, privately on your device.",
     at: NSPoint(x: left, y: y), size: 100, weight: .regular,
     color: NSColor(white: 1, alpha: 0.82), width: 2000, lineSpacing: 16)

// MARK: Right: two phones

func phone(_ path: String, height: CGFloat, center: NSPoint) {
    let screen = image(path)
    let aspect = screen.size.width / screen.size.height
    let bezel: CGFloat = height * 0.018
    let screenRect = NSRect(x: center.x - height * aspect / 2, y: center.y - height / 2,
                            width: height * aspect, height: height)
    let bodyRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
    let radius = height * 0.072

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 120
    shadow.shadowOffset = NSSize(width: 0, height: -50)
    shadow.set()
    rgb(16, 18, 28).setFill()
    NSBezierPath(roundedRect: bodyRect, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    screen.draw(in: screenRect)
    NSGraphicsContext.restoreGraphicsState()
}

phone(args[2], height: 2050, center: NSPoint(x: 3330, y: 1400))
phone(args[3], height: 2200, center: NSPoint(x: 4400, y: 1500))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[4]))
print("wrote \(args[4]) (\(Int(W))×\(Int(H)))")
