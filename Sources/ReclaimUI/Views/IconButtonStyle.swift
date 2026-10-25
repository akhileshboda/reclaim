import SwiftUI

extension View {
    /// Gives an icon-only control at least the HIG's 24 pt target for bezel-less elements, and
    /// makes the whole frame clickable, not just the glyph.
    func iconHitTarget() -> some View {
        frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
    }
}
