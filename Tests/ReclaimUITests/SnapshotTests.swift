import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// Renders the real views with fixture data to PNG (light and dark) so a human, or the HIG
/// review, can inspect them. Files land in $RECLAIM_SANDBOX_DIR/snapshots.
@MainActor @Suite(.serialized) struct SnapshotTests {
    static var outputDirectory: URL {
        let base = ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"] ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: base).appendingPathComponent("snapshots")
    }

    func write(_ name: String, _ view: some View, width: CGFloat = PanelView.width) throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for dark in [false, true] {
            let data = try #require(SnapshotRenderer.png(view, width: width, dark: dark))
            #expect(data.count > 1_000)
            try data.write(to: Self.outputDirectory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
    }

    struct StaticProvider: VolumeProviding {
        let drives: [DriveInfo]
        func mountedDrives() -> [DriveInfo] { drives }
    }

    struct StaticScanner: TrashScanning {
        let summaries: [String: TrashSummary]
        func scan(root: URL, largestCount: Int) -> TrashSummary {
            summaries.first { root.path.hasPrefix($0.key) }?.value ?? .empty
        }
    }

    static let sampleDrives = [
        DriveInfo(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalBytes: 494_000_000_000, freeBytes: 61_000_000_000,
                  importantFreeBytes: 83_000_000_000, isBoot: true, isInternal: true),
        DriveInfo(url: URL(fileURLWithPath: "/Volumes/Footage SSD"), name: "Footage SSD", totalBytes: 2_000_000_000_000,
                  freeBytes: 310_000_000_000, importantFreeBytes: 310_000_000_000, isEjectable: true),
        DriveInfo(url: URL(fileURLWithPath: "/Volumes/KINGSTON"), name: "KINGSTON", totalBytes: 64_000_000_000,
                  freeBytes: 21_000_000_000, isRemovable: true, isEjectable: true),
    ]

    static func item(_ name: String, _ bytes: Int64, dir: Bool = false) -> TrashItem {
        TrashItem(url: URL(fileURLWithPath: "/Volumes/Footage SSD/.Trashes/501/\(name)"), name: name, bytes: bytes, isDirectory: dir, dateDeleted: nil)
    }

    func model(home: TrashSummary) async -> AppModel {
        let scanner = StaticScanner(summaries: [
            "/Users": home,
            "/Volumes/Footage SSD": TrashSummary(access: .readable, itemCount: 214, totalBytes: 186_400_000_000, largestItems: [
                Self.item("A001_C014_interview.mov", 92_000_000_000),
                Self.item("Old Proxies", 61_000_000_000, dir: true),
                Self.item("Render Cache", 33_400_000_000, dir: true),
            ]),
            "/Volumes/KINGSTON": .empty,
        ])
        let model = AppModel(
            mode: .live,
            settings: AppSettings(store: InMemorySettingsStore()),
            confirmer: ScriptedConfirmer(answer: false),
            provider: StaticProvider(drives: Self.sampleDrives),
            locator: TrashLocator(mode: .live, homeDirectory: URL(fileURLWithPath: "/Users/sample"), userID: 501),
            scanner: scanner
        )
        await model.refresh()
        return model
    }

    @Test func panelWithTrash() async throws {
        let home = TrashSummary(access: .readable, itemCount: 38, totalBytes: 4_200_000_000, largestItems: [])
        try write("panel", PanelView(model: await model(home: home)))
    }

    @Test func panelWithTrashPeek() async throws {
        let home = TrashSummary(access: .readable, itemCount: 38, totalBytes: 4_200_000_000, largestItems: [])
        let model = await model(home: home)
        try write("panel-peek", PanelView(model: model, expandedTrashPeeks: ["/Volumes/Footage SSD"]))
    }

    @Test func panelNeedingFullDiskAccess() async throws {
        try write("panel-fda", PanelView(model: await model(home: .denied)))
    }

    @Test func panelWithNotice() async throws {
        let model = await model(home: .empty)
        model.notice = Notice(kind: .success, text: "Reclaimed 186.4 GB on “Footage SSD”.", reclaimedSpace: true)
        try write("panel-notice", PanelView(model: model))
    }

    @Test func emptyStates() async throws {
        let model = AppModel(
            mode: .sandbox,
            settings: AppSettings(store: InMemorySettingsStore()),
            confirmer: ScriptedConfirmer(answer: false),
            provider: StaticProvider(drives: [])
        )
        await model.refresh()
        try write("panel-nodrives", PanelView(model: model))
    }

    @Test func accessibilityValueDescribesEverySegment() {
        let value = BreakdownBar.accessibilityValue(for: SpaceBreakdown(total: 1_000_000_000, free: 200_000_000, importantFree: 300_000_000, trash: 50_000_000))
        #expect(value.contains("used"))
        #expect(value.contains("in Trash"))
        #expect(value.contains("purgeable"))
        #expect(value.contains("free of"))
    }
}
