// Draws Reclaim's app icon and writes an .icns file.
// Usage: swift Scripts/make-icon.swift Resources/AppIcon.icns
//
// Drawn from scratch (SF Symbols may not be used in app icons) on the macOS icon grid:
// 1024 pt canvas, 824 pt rounded-square body, soft drop shadow.

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    // Body with shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32).cgColor)
    color(0x1E5BD8).setFill()
    bodyPath.fill()
    ctx.restoreGState()

    // Background gradient: bright blue at the top to deep blue at the bottom.
    ctx.saveGState()
    bodyPath.addClip()
    NSGradient(colors: [color(0x4FA3FF), color(0x2563EB), color(0x1A3FA8)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -90)
    // Soft top highlight.
    NSGradient(colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)])!
        .draw(in: CGRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
    ctx.restoreGState()

    // Reclaim arrow: an orange 300° circle around the drive, open at the top right.
    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 268
    let startAngle: CGFloat = 70, endAngle: CGFloat = 10 // counter-clockwise from 70° round to 10°
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
    arc.lineWidth = 62
    arc.lineCapStyle = .round
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x0A1F5C, 0.4).cgColor)
    color(0xFF9F0A).setStroke()
    arc.stroke()
    // Arrowhead at the arc's end, aligned with the counter-clockwise tangent there.
    let theta = endAngle * .pi / 180
    let end = CGPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
    let forward = CGPoint(x: -sin(theta), y: cos(theta))
    let outward = CGPoint(x: cos(theta), y: sin(theta))
    let tip = CGPoint(x: end.x + forward.x * 92, y: end.y + forward.y * 92)
    let base = CGPoint(x: end.x - forward.x * 12, y: end.y - forward.y * 12)
    let head = NSBezierPath()
    head.move(to: tip)
    head.line(to: CGPoint(x: base.x + outward.x * 78, y: base.y + outward.y * 78))
    head.line(to: CGPoint(x: base.x - outward.x * 78, y: base.y - outward.y * 78))
    head.close()
    color(0xFF9F0A).setFill()
    head.fill()
    ctx.restoreGState()

    // The drive: a light slab with vents and a status light, centred inside the arrow.
    let drive = CGRect(x: 302, y: 427, width: 420, height: 170)
    let drivePath = NSBezierPath(roundedRect: drive, xRadius: 42, yRadius: 42)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x0A1F5C, 0.45).cgColor)
    color(0xF4F7FB).setFill()
    drivePath.fill()
    ctx.restoreGState()
    ctx.saveGState()
    drivePath.addClip()
    NSGradient(colors: [color(0xFFFFFF), color(0xDCE4EF)])!.draw(in: drive, angle: -90)
    ctx.restoreGState()
    color(0xB9C5D6).setFill()
    NSBezierPath(rect: CGRect(x: 326, y: 482, width: 372, height: 5)).fill()
    color(0x9AA8BC).setFill()
    for i in 0..<4 {
        NSBezierPath(roundedRect: CGRect(x: 342 + CGFloat(i) * 36, y: 444, width: 20, height: 24), xRadius: 6, yRadius: 6).fill()
    }
    color(0x34C759).setFill()
    NSBezierPath(ovalIn: CGRect(x: 656, y: 442, width: 30, height: 30)).fill()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    drawIcon(in: context.cgContext, size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Reclaim-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let preview = output.deletingPathExtension().appendingPathExtension("png")
try png(size: 1024).write(to: preview)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "wrote \(output.path) and \(preview.path)" : "iconutil failed")
