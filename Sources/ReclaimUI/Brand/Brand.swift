import AppKit
import SwiftUI

/// Reclaim's brand: a boomerang, because what you throw away comes back. Ember (the orange of
/// the Trash segment, the space you're about to get back) on Ink (a night-sky navy).
/// See docs/brand.md for the full guide.
public enum Brand {
    public static let tagline = "Get your disk space back."

    /// The app icon's gradients, for the mark in the panel and Settings.
    static let ink = LinearGradient(colors: [Color(hex: 0x2D4290), Color(hex: 0x172460), Color(hex: 0x0A1030)],
                                    startPoint: .top, endPoint: .bottom)
    static let ember = LinearGradient(colors: [Color(hex: 0xFFC46B), Color(hex: 0xFF8F24), Color(hex: 0xEC530A)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Ember for text: dark enough to read on a light popover (about 5:1 on white) and light enough
    /// on a dark one, where plain orange would fail contrast.
    static let emberText = Color(nsColor: NSColor(name: "ReclaimEmberText") { appearance in
        appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(srgbRed: 1, green: 0.663, blue: 0.302, alpha: 1)     // #FFA94D
            : NSColor(srgbRed: 0.761, green: 0.255, blue: 0.047, alpha: 1) // #C2410C
    })

    /// The boomerang as a menu bar template image, so the menu bar tints it for light, dark and
    /// highlighted states like any system glyph.
    @MainActor public static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(BrandGeometry.boomerang(fittingIn: rect.insetBy(dx: 1, dy: 0.5)))
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Reclaim"
        return image
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The boomerang, fitted to whatever frame it's given. SwiftUI's y axis points down, so the
/// design-space path is flipped to keep the elbow at the top left.
public struct BoomerangShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let flipped = CGRect(x: rect.minX, y: -rect.maxY, width: rect.width, height: rect.height)
        return Path(BrandGeometry.boomerang(fittingIn: flipped)).applying(CGAffineTransform(scaleX: 1, y: -1))
    }
}

/// The app icon in miniature: an Ember boomerang on an Ink rounded square.
public struct BrandBadge: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Brand.ink)
            .overlay {
                BoomerangShape()
                    .fill(Brand.ember)
                    .padding(size * 0.2)
                    .shadow(color: .black.opacity(0.35), radius: size * 0.03, y: size * 0.02)
            }
            .overlay {
                // A hairline so the badge holds its edge on a dark popover.
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A boomerang in flight: Reclaim's progress indicator. Falls back to the system spinner when
/// Reduce Motion is on.
struct BoomerangSpinner: View {
    var size: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        if reduceMotion {
            ProgressView().controlSize(.small)
        } else {
            BoomerangShape()
                .fill(Brand.ember)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(spinning ? -360 : 0))
                .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
                .onAppear { spinning = true }
                .accessibilityElement()
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityLabel("In progress")
        }
    }
}
