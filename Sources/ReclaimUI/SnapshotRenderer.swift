import AppKit
import SwiftUI

/// Renders a SwiftUI view, including AppKit-backed controls, to PNG without any screen-capture
/// permission. `ImageRenderer` can't draw buttons and menus on macOS, so this hosts the view in
/// an off-screen window and uses `cacheDisplay`. Used by tests and the app's `--capture` mode.
@MainActor
public enum SnapshotRenderer {
    public static func png<Content: View>(
        _ view: Content,
        width: CGFloat,
        dark: Bool,
        background: NSColor = .windowBackgroundColor
    ) -> Data? {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let root = view
            .frame(width: width)
            .background(Color(nsColor: background))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.entranceAnimations, false)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.display()
        defer { window.close() }

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
