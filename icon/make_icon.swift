// Draws the app icon: a printer (frame + bed) with an eye peeking out. Toothpeek = toothpick + peek.
// Run: swift icon/make_icon.swift   (writes icon/AppIcon.icns). Menu bar version: ToothpeekApp's menuBarIcon in main.swift.
import AppKit

let accent = NSColor(red: 0, green: 174 / 255, blue: 66 / 255, alpha: 1) // Bambu Lab green #00AE42

func circle(_ c: NSPoint, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

func eye(_ c: NSPoint, width w: CGFloat, height h: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x - w / 2, y: c.y))
    p.curve(to: NSPoint(x: c.x + w / 2, y: c.y), controlPoint1: NSPoint(x: c.x - w / 4, y: c.y + h), controlPoint2: NSPoint(x: c.x + w / 4, y: c.y + h))
    p.curve(to: NSPoint(x: c.x - w / 2, y: c.y), controlPoint1: NSPoint(x: c.x + w / 4, y: c.y - h), controlPoint2: NSPoint(x: c.x - w / 4, y: c.y - h))
    p.close()
    return p
}

let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
    // macOS icon grid: 824 pt body centered in 1024.
    let background = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.08, alpha: 1))!.draw(in: background, angle: -90)

    NSColor.white.setStroke()
    let frame = NSBezierPath(roundedRect: NSRect(x: 250, y: 230, width: 524, height: 580), xRadius: 60, yRadius: 60)
    frame.lineWidth = 50
    frame.stroke()

    let c = NSPoint(x: 512, y: 560)
    NSColor.white.setFill()
    eye(c, width: 360, height: 170).fill()
    accent.setFill()
    circle(c, 72).fill()
    NSColor(white: 0.1, alpha: 1).setFill()
    circle(c, 32).fill()

    accent.setFill()
    NSBezierPath(roundedRect: NSRect(x: 330, y: 300, width: 364, height: 40), xRadius: 20, yRadius: 20).fill() // print bed
    return true
}

let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote icon/AppIcon.icns" : "iconutil failed")
