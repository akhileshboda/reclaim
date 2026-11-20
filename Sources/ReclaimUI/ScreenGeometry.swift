import AppKit

/// Screen maths for placing the panel, kept apart from AppKit objects where possible so it can
/// be tested with plain rectangles.
public enum ScreenGeometry {
    /// Whether `frame` (a status item's window) lies wholly on `screenFrame` and clear of the
    /// camera housing between the two `auxiliary` top areas of a notched display.
    public static func isFullyVisible(_ frame: CGRect, screenFrame: CGRect, topLeftArea: CGRect?, topRightArea: CGRect?) -> Bool {
        guard frame.width > 0, frame.height > 0, screenFrame.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
        if let notch = notchRect(screenFrame: screenFrame, topLeftArea: topLeftArea, topRightArea: topRightArea),
           notch.intersects(frame.insetBy(dx: 1, dy: 0)) {
            return false
        }
        return true
    }

    /// The camera housing on a notched display, in global coordinates.
    static func notchRect(screenFrame: CGRect, topLeftArea: CGRect?, topRightArea: CGRect?) -> CGRect? {
        guard var left = topLeftArea, var right = topRightArea, !left.isEmpty, !right.isEmpty else { return nil }
        // The auxiliary areas are documented in screen coordinates; on a secondary display some
        // releases report them relative to the screen's origin instead. Accept either.
        if !screenFrame.insetBy(dx: -1, dy: -1).contains(left) { left = left.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY) }
        if !screenFrame.insetBy(dx: -1, dy: -1).contains(right) { right = right.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY) }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        let height = max(left.height, right.height)
        return CGRect(x: left.maxX, y: screenFrame.maxY - height, width: width, height: height)
    }

    @MainActor public static func isFullyVisible(_ frame: CGRect, on screen: NSScreen) -> Bool {
        isFullyVisible(frame, screenFrame: screen.frame, topLeftArea: screen.auxiliaryTopLeftArea, topRightArea: screen.auxiliaryTopRightArea)
    }

    /// Where a window of `size` goes so its top right corner sits `inset` points inside
    /// `visibleFrame`, clamped so the whole window stays on that screen.
    public static func topRightFrame(size: CGSize, in visibleFrame: CGRect, inset: CGFloat = 12) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let x = max(visibleFrame.minX, visibleFrame.maxX - inset - width)
        let y = max(visibleFrame.minY, visibleFrame.maxY - inset - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Keeps `frame`'s top edge at `top` after a resize, then pulls it back inside `visibleFrame`.
    public static func pinningTop(_ frame: CGRect, top: CGFloat, in visibleFrame: CGRect) -> CGRect {
        var result = frame
        result.size.height = min(frame.height, visibleFrame.height)
        result.origin.y = min(top, visibleFrame.maxY) - result.height
        result.origin.y = max(visibleFrame.minY, result.origin.y)
        result.origin.x = min(max(visibleFrame.minX, frame.minX), visibleFrame.maxX - result.width)
        return result
    }

    /// Whether any part of `frame` is on some display (a saved window position may belong to a
    /// display that's been unplugged).
    @MainActor public static func isOnAnyScreen(_ frame: CGRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersection(frame).width >= 80 && $0.visibleFrame.intersection(frame).height >= 40 }
    }

    @MainActor public static func screenWithPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
