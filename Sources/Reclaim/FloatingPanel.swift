import AppKit
import ReclaimUI

/// The panel as a small floating window, used when the menu bar icon can't be seen. Its top
/// edge stays put as the content grows or shrinks (an NSWindow keeps its bottom edge, which
/// would push the title bar up under the menu bar), and it never leaves its screen.
@MainActor
final class FloatingPanel: NSPanel {
    private var anchorTop: CGFloat?
    private var isPinning = false

    init(contentViewController: NSViewController) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 400),
                   styleMask: [.titled, .closable], backing: .buffered, defer: true)
        self.contentViewController = contentViewController
        title = "Reclaim"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepTopEdge() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The person dragged it: remember the new top edge.
                guard let self, !self.isPinning else { return }
                self.anchorTop = self.frame.maxY
            }
        }
    }

    override var canBecomeKey: Bool { true }

    func anchor(toTopRightOf visibleFrame: CGRect) {
        let target = ScreenGeometry.topRightFrame(size: frame.size, in: visibleFrame)
        anchorTop = target.maxY
        isPinning = true
        setFrame(target, display: true)
        isPinning = false
    }

    private func keepTopEdge() {
        guard !isPinning, let anchorTop, let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let pinned = ScreenGeometry.pinningTop(frame, top: anchorTop, in: visible)
        guard pinned != frame else { return }
        isPinning = true
        setFrame(pinned, display: true)
        isPinning = false
    }
}
