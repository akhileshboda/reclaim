import CoreGraphics
import Observation

/// How tall the panel may grow on the screen it opens on. The AppKit shell sets it from the
/// screen's visible frame each time the panel opens (and when displays change), so the panel
/// never runs off the bottom of a small or scaled display: the drive list scrolls instead.
@MainActor @Observable
public final class PanelLayout {
    /// The tallest the whole panel may be, in points. `nil` means no limit (screenshots, tests).
    public var availableHeight: CGFloat?

    public init(availableHeight: CGFloat? = nil) {
        self.availableHeight = availableHeight
    }

    /// The scrolling middle never gets shorter than this, even on a tiny screen: enough for one
    /// drive card.
    public static let minimumScrollHeight: CGFloat = 140

    /// The height left for the scrolling middle once the pinned header and footer (`chrome`)
    /// are placed. `nil` when there's no limit.
    public static func scrollHeightLimit(available: CGFloat?, chrome: CGFloat) -> CGFloat? {
        guard let available else { return nil }
        return max(minimumScrollHeight, (available - chrome).rounded(.down))
    }
}
