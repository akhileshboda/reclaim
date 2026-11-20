import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// The panel has to fit the screen it opens on: a beta tester saw it run off a small display.
@MainActor @Suite(.serialized) struct PanelLayoutTests {
    @Test func scrollLimitLeavesRoomForHeaderAndFooter() {
        #expect(PanelLayout.scrollHeightLimit(available: nil, chrome: 200) == nil)
        #expect(PanelLayout.scrollHeightLimit(available: 800, chrome: 200) == 600)
        #expect(PanelLayout.scrollHeightLimit(available: 250, chrome: 200) == PanelLayout.minimumScrollHeight)
    }

    @Test func statusItemBehindTheNotchIsNotVisible() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 660, height: 32)
        let right = CGRect(x: 852, y: 950, width: 660, height: 32)
        let beside = CGRect(x: 900, y: 958, width: 30, height: 24)
        let behind = CGRect(x: 700, y: 958, width: 30, height: 24)
        let offScreen = CGRect(x: 1520, y: 958, width: 30, height: 24)
        #expect(ScreenGeometry.isFullyVisible(beside, screenFrame: screen, topLeftArea: left, topRightArea: right))
        #expect(!ScreenGeometry.isFullyVisible(behind, screenFrame: screen, topLeftArea: left, topRightArea: right))
        #expect(!ScreenGeometry.isFullyVisible(offScreen, screenFrame: screen, topLeftArea: left, topRightArea: right))
        #expect(ScreenGeometry.isFullyVisible(behind, screenFrame: screen, topLeftArea: nil, topRightArea: nil), "no notch, no problem")
    }

    @Test func notchOnASecondaryDisplayWithRelativeAreas() {
        let screen = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        let left = CGRect(x: 0, y: 950, width: 660, height: 32)
        let right = CGRect(x: 852, y: 950, width: 660, height: 32)
        let behind = CGRect(x: -800, y: 958, width: 30, height: 24)
        #expect(!ScreenGeometry.isFullyVisible(behind, screenFrame: screen, topLeftArea: left, topRightArea: right))
    }

    @Test func fallbackWindowOpensTopRightAndStaysOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 775)
        let frame = ScreenGeometry.topRightFrame(size: CGSize(width: 340, height: 900), in: visible)
        #expect(visible.contains(frame))
        #expect(frame.maxX == 1268)

        // Growing content keeps the title bar where it was instead of pushing it up off the screen.
        let grown = CGRect(x: frame.minX, y: frame.minY, width: 340, height: frame.height + 200)
        let pinned = ScreenGeometry.pinningTop(grown, top: frame.maxY, in: visible)
        #expect(pinned.maxY <= visible.maxY)
        #expect(visible.contains(pinned))
    }

    /// Everything that can make the panel tall at once: both banners, a notice, three drives and
    /// an open Trash peek, on a 13-inch MacBook Air at "Larger Text" (about 600 pt below the menu bar).
    @Test func crowdedPanelFitsASmallScreen() async throws {
        let model = await SnapshotTests().model(home: .denied)
        model.availableUpdate = try JSONDecoder().decode(Release.self, from: Data(#"{"tag_name":"v9.0.0","html_url":"https://example.com","draft":false,"prerelease":false}"#.utf8))
        model.notice = Notice(kind: .success, text: "Reclaimed 186.4 GB on “Footage SSD”.", reclaimedSpace: true)
        let layout = PanelLayout(availableHeight: 600)
        let panel = PanelView(model: model, layout: layout, expandedTrashPeeks: ["/Volumes/Footage SSD"])

        let unlimited = Self.fittingHeight(PanelView(model: model, expandedTrashPeeks: ["/Volumes/Footage SSD"]))
        #expect(unlimited > 600, "the fixture really is taller than the screen")
        #expect(Self.fittingHeight(panel) <= 600)
    }

    static func fittingHeight(_ view: some View) -> CGFloat {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: PanelView.width, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // A few layout passes so measured header and footer heights settle.
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        defer { window.close() }
        return hosting.fittingSize.height
    }
}
