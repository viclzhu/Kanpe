// Draws Kanpe's app icon: カンペ on a cue card.
//   swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.92, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.95, alpha: 1),
               ending: NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.82, alpha: 1))!
        .draw(in: body, angle: -90)
    // Ruled lines, like a card.
    NSColor(calibratedRed: 0.55, green: 0.70, blue: 0.85, alpha: 0.35).setFill()
    NSRect(x: 100, y: 240, width: 824, height: 5).fill()
    // Red margin line.
    NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.35, alpha: 0.55).setFill()
    NSRect(x: 100, y: 790, width: 824, height: 6).fill()
    NSGraphicsContext.restoreGraphicsState()

    let font = NSFont(name: "HiraginoSans-W8", size: 250) ?? NSFont.boldSystemFont(ofSize: 250)
    let text = NSAttributedString(string: "カンペ", attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.16, alpha: 1),
        .kern: -6,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: 512 - size.width / 2, y: 520 - size.height / 2))

    // Marker underline.
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 230, y: 375))
    line.curve(to: NSPoint(x: 800, y: 390), controlPoint1: NSPoint(x: 420, y: 357), controlPoint2: NSPoint(x: 620, y: 397))
    line.lineWidth = 34
    line.lineCapStyle = .round
    NSColor(calibratedRed: 0.93, green: 0.36, blue: 0.27, alpha: 1).setStroke()
    line.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("Kanpe-\(UUID().uuidString).iconset")
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: URL(fileURLWithPath: "/tmp/kanpe-icon-preview.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run(); task.waitUntilExit()
try? fm.removeItem(at: iconset)
print("Wrote \(out)")
