// Composes the App Store screenshots: headline on top, the app screen below, in the app's colours.
// usage: swift tools/screenshot_store.swift <output.jpg> <screen.png> "<title>" "<subtitle>"
import AppKit

let args = CommandLine.arguments
guard args.count == 5, let screen = NSImage(contentsOfFile: args[2]) else {
    print("usage: swift tools/screenshot_store.swift <output.jpg> <screen.png> <title> <subtitle>")
    exit(1)
}
let output = args[1], title = args[3], subtitle = args[4]

// iPhone 6.9" display, the size App Store Connect asks for.
let width = 1320, height = 2868
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
// Drawn fully opaque; the JPEG output drops the alpha channel, which App Store screenshots must not have.
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
let canvas = NSRect(x: 0, y: 0, width: width, height: height)

// Night background with a warm sunrise glow from the bottom.
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.24, alpha: 1),
                    NSColor(srgbRed: 0.027, green: 0.031, blue: 0.06, alpha: 1)])!
    .draw(in: canvas, angle: -90)
NSGradient(colors: [NSColor(srgbRed: 1, green: 0.56, blue: 0.24, alpha: 0.45),
                    NSColor(srgbRed: 1, green: 0.56, blue: 0.24, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: 660, y: 0), radius: 0, toCenter: NSPoint(x: 660, y: 0), radius: 1500, options: [])

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

let centered = NSMutableParagraphStyle()
centered.alignment = .center
centered.lineSpacing = 6

NSAttributedString(string: title, attributes: [
    .font: rounded(104, .bold),
    .foregroundColor: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 1),
    .paragraphStyle: centered,
]).draw(with: NSRect(x: 80, y: 2310, width: 1160, height: 330), options: [.usesLineFragmentOrigin])

NSAttributedString(string: subtitle, attributes: [
    .font: rounded(50, .medium),
    .foregroundColor: NSColor(srgbRed: 1, green: 0.72, blue: 0.45, alpha: 1),
    .paragraphStyle: centered,
]).draw(with: NSRect(x: 110, y: 2120, width: 1100, height: 170), options: [.usesLineFragmentOrigin])

// The app screen, slightly cropped at the bottom edge.
let screenWidth: CGFloat = 1040
let screenHeight = screenWidth * screen.size.height / screen.size.width
let frame = NSRect(x: (CGFloat(width) - screenWidth) / 2, y: 2040 - screenHeight, width: screenWidth, height: screenHeight)
let shape = NSBezierPath(roundedRect: frame, xRadius: 110, yRadius: 110)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(srgbRed: 1, green: 0.56, blue: 0.24, alpha: 0.35)
shadow.shadowBlurRadius = 90
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
shape.addClip()
screen.draw(in: frame)
NSGraphicsContext.restoreGraphicsState()
NSColor(srgbRed: 0.15, green: 0.16, blue: 0.25, alpha: 1).setStroke()
shape.lineWidth = 8
shape.stroke()

NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
try! data.write(to: URL(fileURLWithPath: output))
