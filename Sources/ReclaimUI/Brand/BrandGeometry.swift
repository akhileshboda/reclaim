import CoreGraphics
import Foundation

/// The geometry of Reclaim's mark, a boomerang: what you throw away comes back.
///
/// One source of truth for the app icon (`Scripts/make-icon.swift` compiles this file alongside
/// it), the menu bar glyph and the logo in the panel. CoreGraphics only, so the icon script can
/// use it without AppKit or SwiftUI.
public enum BrandGeometry {
    /// The boomerang drawn in a 1024 × 1024 design space (y up), as a union of discs along a
    /// tapered centreline. Fill it with the non-zero rule (the default) and the discs merge into
    /// one smooth silhouette with round tips.
    /// `nonisolated(unsafe)`: CGPath isn't marked Sendable, but this one is built once and never
    /// mutated, so sharing it across threads is safe.
    nonisolated(unsafe) public static let boomerang: CGPath = {
        let (points, elbowFraction) = centreline(tipA: CGPoint(x: 372, y: 300), elbow: CGPoint(x: 300, y: 694), tipB: CGPoint(x: 736, y: 716))
        let path = CGMutablePath()
        for (point, t) in points {
            // Widest at the elbow, tapering towards both tips like a real boomerang's wings.
            let k = t < elbowFraction ? t / elbowFraction : (1 - t) / (1 - elbowFraction)
            let radius = (tipWidth + (elbowWidth - tipWidth) * (1 - (1 - k) * (1 - k))) / 2
            path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }()

    /// The dotted return flight in the app icon, in the same space: a spiral from below the
    /// trailing tip, round under the boomerang, back up to the leading tip (angles in radians).
    public static let trail = (center: CGPoint(x: 520, y: 500), startAngle: CGFloat.pi * 1.36, endAngle: CGFloat.pi * 2.14,
                               startRadius: CGFloat(300), endRadius: CGFloat(350))

    /// The boomerang scaled to fit `rect`, centred, keeping its proportions.
    public static func boomerang(fittingIn rect: CGRect) -> CGPath {
        let box = boomerang.boundingBoxOfPath
        let scale = min(rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -box.midX, y: -box.midY)
        return boomerang.copy(using: &transform) ?? boomerang
    }

    private static let tipWidth: CGFloat = 84
    private static let elbowWidth: CGFloat = 170

    /// Points along one smooth cubic from tip A round the elbow to tip B, each with its fraction
    /// of the total length, plus the fraction where the curve passes closest to the elbow.
    private static func centreline(tipA a: CGPoint, elbow e: CGPoint, tipB b: CGPoint) -> ([(CGPoint, CGFloat)], CGFloat) {
        let pull: CGFloat = 0.74 // how tightly the curve hugs the elbow
        let c1 = CGPoint(x: a.x + (e.x - a.x) * pull, y: a.y + (e.y - a.y) * pull)
        let c2 = CGPoint(x: b.x + (e.x - b.x) * pull, y: b.y + (e.y - b.y) * pull)
        let samples = 240
        let points = (0...samples).map { i -> CGPoint in
            let t = CGFloat(i) / CGFloat(samples), mt = 1 - t
            let w0 = mt * mt * mt, w1 = 3 * mt * mt * t, w2 = 3 * mt * t * t, w3 = t * t * t
            return CGPoint(x: w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x, y: w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y)
        }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count { lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)) }
        let total = lengths[lengths.count - 1]
        let nearest = points.indices.min { hypot(points[$0].x - e.x, points[$0].y - e.y) < hypot(points[$1].x - e.x, points[$1].y - e.y) }!
        return (zip(points, lengths).map { ($0, $1 / total) }, lengths[nearest] / total)
    }
}
