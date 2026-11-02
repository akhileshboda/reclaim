// Draws Reclaim's app icon and writes an .icns file plus a 1024 px PNG preview.
// Usage: make icon (compiles this file with Sources/ReclaimUI/Brand/BrandGeometry.swift, the
// shared shape of the boomerang mark, then runs it with the output path).
//
// Drawn from scratch (SF Symbols may not be used in app icons) on the macOS icon grid:
// 1024 pt canvas, 824 pt rounded-square body, soft drop shadow. Colours follow docs/brand.md.

import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
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
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func gradient(_ colors: [UInt32], _ locations: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map { color($0) } as CFArray, locations: locations)!
    }

    static func drawIcon(in ctx: CGContext, size: CGFloat) {
        ctx.scaleBy(x: size / 1024, y: size / 1024)
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Body with shadow, filled with the Ink gradient: dusk blue at the top to night at the bottom.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.32))
        ctx.addPath(bodyPath)
        ctx.setFillColor(color(0x0A1030))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(bodyPath)
        ctx.clip()
        ctx.drawLinearGradient(gradient([0x2D4290, 0x172460, 0x0A1030], [0, 0.5, 1]),
                               start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        // A warm glow where the boomerang turns, as if it lit the sky on its way back.
        ctx.drawRadialGradient(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                          colors: [color(0xFF8F24, 0.18), color(0xFF8F24, 0)] as CFArray, locations: [0, 1])!,
                               startCenter: CGPoint(x: 360, y: 640), startRadius: 0,
                               endCenter: CGPoint(x: 360, y: 640), endRadius: 420, options: [])
        drawTrail(in: ctx)
        ctx.restoreGState()

        drawBoomerang(in: ctx)
    }

    /// The return flight: a dotted trail that leaves the trailing tip, swings round below and
    /// comes back to the leading tip, its dots growing and brightening on the way home.
    static func drawTrail(in ctx: CGContext) {
        let trail = BrandGeometry.trail
        let dots = 22
        for i in 0..<dots {
            let progress = CGFloat(i) / CGFloat(dots - 1)
            let angle = trail.startAngle + (trail.endAngle - trail.startAngle) * progress
            let distance = trail.startRadius + (trail.endRadius - trail.startRadius) * progress
            let point = CGPoint(x: trail.center.x + cos(angle) * distance, y: trail.center.y + sin(angle) * distance)
            let radius = 4 + 6 * progress
            ctx.setFillColor(color(0xA9C4FF, 0.14 + 0.5 * progress))
            ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    static func drawBoomerang(in ctx: CGContext) {
        let shape = BrandGeometry.boomerang

        // Ember body with a soft, deep shadow.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: color(0x02040F, 0.55))
        ctx.addPath(shape)
        ctx.setFillColor(color(0xFF8F24))
        ctx.fillPath()
        ctx.restoreGState()

        // A light rim along the upper edges: fill the highlight, then cover all of it except a
        // thin sliver with the body gradient drawn through a copy of the shape nudged down-right.
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.setFillColor(color(0xFFE2B0))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        var nudge = CGAffineTransform(translationX: 9, y: -13)
        ctx.addPath(shape.copy(using: &nudge)!)
        ctx.clip()
        ctx.drawLinearGradient(gradient([0xFFC46B, 0xFF8F24, 0xEC530A], [0, 0.45, 1]),
                               start: CGPoint(x: 290, y: 760), end: CGPoint(x: 660, y: 380), options: [])
        ctx.restoreGState()
    }

    static func png(size: Int) -> Data {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        drawIcon(in: ctx, size: CGFloat(size))
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }
}
