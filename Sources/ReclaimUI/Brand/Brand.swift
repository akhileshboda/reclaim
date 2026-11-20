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

// MARK: - Motion

/// Reclaim's motion tokens. Strong curves rather than SwiftUI's built-in ones, which are too
/// weak to read as deliberate. Everything checks Reduce Motion at the call site.
enum Motion {
    /// Entering, exiting and value changes.
    static func easeOut(_ duration: Double = 0.3) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    /// Something travelling across the panel.
    static func easeInOut(_ duration: Double = 0.4) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: duration) }
    /// Hover tints.
    static let hover = Animation.easeOut(duration: 0.15)
}

/// Turns off one-off entrance animations, so snapshots and captures show the settled panel.
private struct EntranceAnimationsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    public var entranceAnimations: Bool {
        get { self[EntranceAnimationsKey.self] }
        set { self[EntranceAnimationsKey.self] = newValue }
    }
}

// MARK: - Surfaces

extension Brand {
    /// The one Ember button (Empty All Trash). Dark enough for white text in both appearances.
    static let emberButton = Color(hex: 0xC2410C)
    /// Card corner radius, shared by drive cards, banners and the hero.
    static let cardRadius: CGFloat = 12
}

extension View {
    /// The rounded, softly filled surface used for drive cards and banners.
    func cardBackground(highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(Color(nsColor: highlighted ? .tertiarySystemFill : .quaternarySystemFill))
        )
    }
}

// MARK: - Hero ring

/// The hero gauge. The Ember arc is how much the free space on the drives grows when their Trash
/// is emptied (reclaimable ÷ (free + reclaimable)), so a big win looks big. A full green ring with
/// a checkmark means there's nothing to reclaim.
struct ReclaimRing: View {
    enum Content: Equatable { case measuring, clear, reclaimable(fraction: Double), idle }

    let content: Content
    var size: CGFloat = 64
    /// Changes each time space comes back; the ring gives a little bounce as the boomerang lands.
    var pulse: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { size * 0.12 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(nsColor: .quaternaryLabelColor).opacity(0.5), lineWidth: lineWidth)
            arc
            center
        }
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: 1.0, trigger: pulse) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            // Hold while the boomerang is in flight, then a quick bounce as it lands.
            LinearKeyframe(1.0, duration: 0.62)
            SpringKeyframe(reduceMotion ? 1.0 : 1.12, duration: 0.14, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.45), value: content)
        .accessibilityHidden(true) // The amount beside it says the same thing in words.
    }

    @ViewBuilder private var arc: some View {
        switch content {
        case .reclaimable(let fraction):
            Circle()
                .trim(from: 0, to: max(0.04, min(1, fraction)))
                .stroke(AngularGradient(colors: [Color(hex: 0xFFC46B), Color(hex: 0xFF8F24), Color(hex: 0xEC530A)],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.04, min(1, fraction)))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Color(hex: 0xFF8F24).opacity(0.45), radius: lineWidth * 0.6)
        case .clear:
            Circle()
                .stroke(Color(nsColor: .systemGreen), lineWidth: lineWidth)
        case .measuring, .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var center: some View {
        switch content {
        case .measuring:
            BoomerangSpinner(size: size * 0.34)
        case .clear:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(Color(nsColor: .systemGreen))
        case .reclaimable:
            BoomerangShape()
                .fill(Brand.ember)
                .frame(width: size * 0.36, height: size * 0.36)
        case .idle:
            BoomerangShape()
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: size * 0.36, height: size * 0.36)
        }
    }
}

// MARK: - Celebration

/// An Ember boomerang that spins along an arc from `start` to `end` when `trigger` changes:
/// the space you threw away coming back. Draws nothing at rest or under Reduce Motion.
struct BoomerangFlight: View {
    let trigger: Int
    let start: CGPoint
    let end: CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            KeyframeAnimator(initialValue: FlightFrame(), trigger: trigger) { frame in
                BoomerangShape()
                    .fill(Brand.ember)
                    .frame(width: 26, height: 26)
                    .shadow(color: Color(hex: 0xFF8F24).opacity(0.6), radius: 6)
                    .rotationEffect(.degrees(frame.progress * -900))
                    .scaleEffect(frame.scale)
                    .opacity(frame.opacity)
                    .position(point(at: frame.progress))
            } keyframes: { _ in
                KeyframeTrack(\.progress) {
                    LinearKeyframe(0, duration: 0.05)
                    CubicKeyframe(1, duration: 0.6)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.7, duration: 0.05)
                    CubicKeyframe(1.25, duration: 0.3)
                    CubicKeyframe(0.55, duration: 0.3)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.08)
                    LinearKeyframe(1, duration: 0.5)
                    LinearKeyframe(0, duration: 0.1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// A quadratic curve that swings out to the right, like a boomerang's return.
    private func point(at t: Double) -> CGPoint {
        let control = CGPoint(x: max(start.x, end.x) + 140, y: (start.y + end.y) / 2)
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }
}

private struct FlightFrame {
    var progress: Double = 0
    var scale: Double = 0.7
    /// Hidden at rest; the keyframes fade it in only while it flies.
    var opacity: Double = 0
}

// MARK: - Ember button

/// The panel's one call to action. Drawn by hand rather than `.borderedProminent`, which turns
/// grey whenever the popover isn't the key window.
struct EmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled
                          ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xEA580C), Brand.emberButton], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color(nsColor: .quaternarySystemFill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled && contrast != .increased ? 0.18 : 0), lineWidth: 0.5)
            )
            .brightness(configuration.isPressed ? -0.08 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
