import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("missing iconset output directory\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes = [16, 32, 128, 256, 512]
let mint = NSColor(calibratedRed: 0.26, green: 0.92, blue: 0.70, alpha: 1)
let cyan = NSColor(calibratedRed: 0.20, green: 0.68, blue: 0.90, alpha: 1)
let graphite = NSColor(calibratedWhite: 0.10, alpha: 1)
let ink = NSColor(calibratedWhite: 0.94, alpha: 1)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.current?.imageInterpolation = .high

    let background = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.025, dy: size * 0.025), xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(starting: cyan, ending: mint)?.draw(in: background, angle: -35)

    let center = NSPoint(x: size * 0.5, y: size * 0.5)
    let diskRadius = size * 0.29
    let diskRect = NSRect(x: center.x - diskRadius, y: center.y - diskRadius, width: diskRadius * 2, height: diskRadius * 2)
    graphite.setFill()
    NSBezierPath(ovalIn: diskRect).fill()

    NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
    let ring = NSBezierPath(ovalIn: diskRect.insetBy(dx: size * 0.055, dy: size * 0.055))
    ring.lineWidth = max(1, size * 0.018)
    ring.stroke()

    mint.setFill()
    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: size * 0.50, y: size * 0.29))
    shield.line(to: NSPoint(x: size * 0.65, y: size * 0.35))
    shield.line(to: NSPoint(x: size * 0.63, y: size * 0.51))
    shield.curve(to: NSPoint(x: size * 0.50, y: size * 0.66), controlPoint1: NSPoint(x: size * 0.62, y: size * 0.58), controlPoint2: NSPoint(x: size * 0.54, y: size * 0.64))
    shield.curve(to: NSPoint(x: size * 0.37, y: size * 0.51), controlPoint1: NSPoint(x: size * 0.46, y: size * 0.64), controlPoint2: NSPoint(x: size * 0.38, y: size * 0.58))
    shield.line(to: NSPoint(x: size * 0.35, y: size * 0.35))
    shield.close()
    shield.fill()

    ink.setStroke()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: size * 0.42, y: size * 0.47))
    check.line(to: NSPoint(x: size * 0.48, y: size * 0.41))
    check.line(to: NSPoint(x: size * 0.59, y: size * 0.53))
    check.lineWidth = max(1.5, size * 0.035)
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()

    NSColor.white.withAlphaComponent(0.9).setFill()
    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: size * 0.77, y: size * 0.73))
    sparkle.line(to: NSPoint(x: size * 0.795, y: size * 0.795))
    sparkle.line(to: NSPoint(x: size * 0.86, y: size * 0.82))
    sparkle.line(to: NSPoint(x: size * 0.795, y: size * 0.845))
    sparkle.line(to: NSPoint(x: size * 0.77, y: size * 0.91))
    sparkle.line(to: NSPoint(x: size * 0.745, y: size * 0.845))
    sparkle.line(to: NSPoint(x: size * 0.68, y: size * 0.82))
    sparkle.line(to: NSPoint(x: size * 0.745, y: size * 0.795))
    sparkle.close()
    sparkle.fill()

    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CleanMyMacIcon", code: 1)
    }
    try data.write(to: url)
}

for size in sizes {
    try writePNG(image: drawIcon(size: CGFloat(size)), to: outputURL.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(image: drawIcon(size: CGFloat(size * 2)), to: outputURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
