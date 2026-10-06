// Renders the App Store creative assets from two app screenshots: the icon
// and headline on the left, phones on the right.
//
//   header  5244 × 2950  product-page header; key content stays in the middle
//                        band so the wide 3840 × 1646 crop keeps it
//   search  3840 × 2560  search results asset
//
//   swift Tools/generate_header.swift header|search <icon.png> <left-screen.png> <right-screen.png> <out.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 6, ["header", "search"].contains(args[1]) else {
    print("usage: generate_header.swift header|search <icon.png> <left-screen.png> <right-screen.png> <out.png>")
    exit(1)
}

struct Layout {
    var size: NSSize
    var left: CGFloat, iconSize: CGFloat, iconY: CGFloat
    var nameSize: CGFloat, nameTop: CGFloat
    var headlineTop: CGFloat, headlineSize: CGFloat, headlineWidth: CGFloat
    var bodySize: CGFloat, bodyWidth: CGFloat
    var glow: NSRect
    var phones: [(height: CGFloat, center: NSPoint)]
}

let layout: Layout = args[1] == "header"
    ? Layout(size: NSSize(width: 5244, height: 2950),
             left: 400, iconSize: 400, iconY: 1900, nameSize: 150, nameTop: 2190,
             headlineTop: 1760, headlineSize: 215, headlineWidth: 2250, bodySize: 100, bodyWidth: 2000,
             glow: NSRect(x: 2500, y: 200, width: 2700, height: 2550),
             phones: [(2050, NSPoint(x: 3330, y: 1400)), (2200, NSPoint(x: 4400, y: 1500))])
    : Layout(size: NSSize(width: 3840, height: 2560),
             left: 300, iconSize: 320, iconY: 1820, nameSize: 120, nameTop: 2055,
             headlineTop: 1640, headlineSize: 175, headlineWidth: 1800, bodySize: 84, bodyWidth: 1650,
             glow: NSRect(x: 1800, y: 150, width: 2200, height: 2250),
             phones: [(1650, NSPoint(x: 2440, y: 1200)), (1800, NSPoint(x: 3290, y: 1290))])

let W = layout.size.width, H = layout.size.height

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
    .draw(in: NSBezierPath(ovalIn: layout.glow), relativeCenterPosition: .zero)

// MARK: Left: icon, name, headline

let left = layout.left, iconSize = layout.iconSize
let icon = image(args[2])
let iconRect = NSRect(x: left, y: layout.iconY, width: iconSize, height: iconSize)
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

draw("Project Tracker", at: NSPoint(x: left + iconSize * 1.18, y: layout.nameTop), size: layout.nameSize,
     weight: .semibold, color: NSColor(white: 1, alpha: 0.9))
var y = layout.headlineTop
y -= draw("Paste your deadlines.\nGet the whole plan.", at: NSPoint(x: left, y: y), size: layout.headlineSize,
          weight: .bold, color: .white, width: layout.headlineWidth, lineSpacing: 6)
y -= layout.bodySize * 0.9
draw("Apple Intelligence turns your course email into stages, dates and tasks, privately on your device.",
     at: NSPoint(x: left, y: y), size: layout.bodySize, weight: .regular,
     color: NSColor(white: 1, alpha: 0.82), width: layout.bodyWidth, lineSpacing: layout.bodySize * 0.16)

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
    shadow.shadowBlurRadius = height * 0.058
    shadow.shadowOffset = NSSize(width: 0, height: -height * 0.024)
    shadow.set()
    rgb(16, 18, 28).setFill()
    NSBezierPath(roundedRect: bodyRect, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    screen.draw(in: screenRect)
    NSGraphicsContext.restoreGraphicsState()
}

for (path, spec) in zip([args[3], args[4]], layout.phones) {
    phone(path, height: spec.height, center: spec.center)
}

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[5]))
print("wrote \(args[5]) (\(Int(W))×\(Int(H)))")
