import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// Fixes from the beta stability pass: slow drives, extra rescans, misleading messages.
@MainActor @Suite struct StabilityTests {
    /// Two drives; B can be swapped for a different disk with the same name.
    final class TwoDriveProvider: VolumeProviding, @unchecked Sendable {
        let volumes: URL
        private let lock = NSLock()
        private var uuidB = "UUID-B"
        init(volumes: URL) { self.volumes = volumes }
        func swapB() { lock.withLock { uuidB = "UUID-B-OTHER" } }
        func mountedDrives() -> [DriveInfo] {
            let b = lock.withLock { uuidB }
            return [
                DriveInfo(url: volumes.appendingPathComponent("RTEST-A"), name: "RTEST-A", totalBytes: 1_000_000_000,
                          freeBytes: 500_000_000, isEjectable: true, uuid: "UUID-A"),
                DriveInfo(url: volumes.appendingPathComponent("RTEST-B"), name: "RTEST-B", totalBytes: 2_000_000_000,
                          freeBytes: 900_000_000, isEjectable: true, uuid: b),
            ]
        }
    }

    /// Blocks on one Trash until released, like a USB disk spinning up or a hung share.
    final class SlowScanner: TrashScanning, @unchecked Sendable {
        let slowFragment: String
        let release = DispatchSemaphore(value: 0)
        init(slowFragment: String) { self.slowFragment = slowFragment }
        func scan(root: URL, largestCount: Int) -> TrashSummary {
            if root.path.contains(slowFragment) { release.wait() }
            return TrashScanner().scan(root: root, largestCount: largestCount)
        }
    }

    final class RecordingNotifier: LowSpaceNotifying {
        var titles: [String] = []
        func notify(driveID: String, title: String, body: String) { titles.append(title) }
    }

    func model(_ fixture: UIFixture, provider: any VolumeProviding, scanner: any TrashScanning = TrashScanner(),
               confirmer: ScriptedConfirmer = ScriptedConfirmer(answer: true), store: InMemorySettingsStore = InMemorySettingsStore()) -> AppModel {
        AppModel(
            mode: .sandbox, settings: AppSettings(store: store), confirmer: confirmer, provider: provider,
            locator: TrashLocator(mode: .sandbox, homeDirectory: fixture.root, userID: fixture.uid),
            scanner: scanner,
            policy: SafetyPolicy(mode: .sandbox, homeDirectory: fixture.root, volumesDirectory: fixture.volumes, userID: fixture.uid)
        )
    }

    @Test func emptyAllStillEmptiesDrivesThatDidNotChange() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["b.mov": 1_000])
        let provider = TwoDriveProvider(volumes: fixture.volumes)
        let confirmer = ScriptedConfirmer(answer: true)
        let model = model(fixture, provider: provider, confirmer: confirmer)
        await model.refresh()
        confirmer.whileAsking = {
            provider.swapB()
            await model.refresh()
        }

        await model.emptyAllTrash()

        #expect(fixture.trashContents("RTEST-A").isEmpty, "A was confirmed and unchanged")
        #expect(fixture.trashContents("RTEST-B") == ["b.mov"], "B changed during the question")
        let text = try #require(model.notice?.text)
        #expect(text.hasPrefix("Reclaimed "))
        #expect(text.contains("“RTEST-B” changed while Reclaim was asking and was left alone."))
        #expect(model.state(for: fixture.volumes.appendingPathComponent("RTEST-A").path)?.canEmpty == false, "refreshed afterwards")
    }

    @Test func slowDriveDoesNotHoldUpTheOthers() async throws {
        let fixture = try UIFixture()
        let a = try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        let b = try fixture.addVolume("RTEST-B", trashFiles: ["b": 2_000])
        let scanner = SlowScanner(slowFragment: "RTEST-B")
        let model = model(fixture, provider: TwoDriveProvider(volumes: fixture.volumes), scanner: scanner)
        model.scanTimeout = 0.3

        await model.refresh()

        #expect(model.state(for: a.path)?.trash.itemCount == 1)
        #expect(model.state(for: a.path)?.isMeasuring == false)
        #expect(model.state(for: b.path)?.isMeasuring == true, "B shows as still measuring")
        #expect(!model.isRefreshing)

        // A rescan asked for meanwhile doesn't pile another blocked scan onto the slow drive.
        await model.refresh(rescanning: [b.path])
        #expect(!model.isRefreshing)

        scanner.release.signal()
        scanner.release.signal()
        for _ in 0..<100 where model.state(for: b.path)?.isMeasuring != false {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.state(for: b.path)?.isMeasuring == false)
        #expect(model.state(for: b.path)?.trash.itemCount == 1, "the late result arrives")
    }

    @Test func actionsRescanOnlyTheirDrive() async throws {
        let fixture = try UIFixture()
        let a = try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["b": 1_000])
        let scanner = CountingScanner()
        let model = model(fixture, provider: UIFixture.Provider(volumes: fixture.volumes), scanner: scanner)
        await model.refresh()

        await model.emptyTrash(driveID: a.path)

        #expect(scanner.count(containing: "RTEST-A") == 2)
        #expect(scanner.count(containing: "RTEST-B") == 1, "emptying A leaves B's Trash alone")
    }

    @Test func copyingOntoAFreshDriveDoesNotTriggerRescans() async throws {
        let fixture = try UIFixture()
        let fresh = fixture.volumes.appendingPathComponent("RTEST-NEW")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let model = model(fixture, provider: UIFixture.Provider(volumes: fixture.volumes))
        await model.refresh()

        #expect(model.driveIDs(containing: [fresh.path + "/Holiday Photos/2026/"]).isEmpty)
        #expect(model.driveIDs(containing: [fresh.path + "/"]) == [fresh.path], "the Trash folder appearing still counts")
        #expect(model.driveIDs(containing: [fresh.path + "/.Trashes/\(fixture.uid)"]) == [fresh.path])
    }

    @Test func readOnlyDrivesAreNotOfferedEmpty() {
        let drive = DriveInfo(url: URL(fileURLWithPath: "/Volumes/NTFS"), name: "NTFS", totalBytes: 100, freeBytes: 10, isReadOnly: true)
        let state = DriveState(drive: drive, trashURL: URL(fileURLWithPath: "/Volumes/NTFS/.Trashes/501"),
                               trash: TrashSummary(access: .readable, itemCount: 3, totalBytes: 30, largestItems: []))
        #expect(!state.canEmpty)
    }

    @Test func lowSpaceChecksOneVolumePerContainerAndSkipsShares() {
        func state(_ name: String, total: Int64, free: Int64, network: Bool = false, important: Int64? = nil) -> DriveState {
            DriveState(drive: DriveInfo(url: URL(fileURLWithPath: "/Volumes/\(name)"), name: name, totalBytes: total, freeBytes: free,
                                        importantFreeBytes: important, isNetwork: network), trashURL: nil, trash: .empty)
        }
        let candidates = AppModel.lowSpaceCandidates([
            state("Macintosh HD", total: 500, free: 10),
            state("Macintosh HD - Data", total: 500, free: 10),
            state("NAS", total: 1_000, free: 5, network: true),
            state("Unknown", total: 1_000, free: 0),
            state("Stick", total: 64, free: 1),
        ])
        #expect(candidates.map(\.name) == ["Macintosh HD", "Stick"])
    }

    @Test func lowSpaceWarningIsNotRepeatedAfterRelaunch() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        struct FullProvider: VolumeProviding {
            let volumes: URL
            func mountedDrives() -> [DriveInfo] {
                [DriveInfo(url: volumes.appendingPathComponent("RTEST-A"), name: "RTEST-A", totalBytes: 1_000_000_000, freeBytes: 10_000_000)]
            }
        }
        let store = InMemorySettingsStore()
        let first = RecordingNotifier()
        let model1 = model(fixture, provider: FullProvider(volumes: fixture.volumes), store: store)
        model1.lowSpaceNotifier = first
        await model1.refresh()
        #expect(first.titles.count == 1)

        let second = RecordingNotifier()
        let model2 = model(fixture, provider: FullProvider(volumes: fixture.volumes), store: store)
        model2.lowSpaceNotifier = second
        await model2.refresh()
        #expect(second.titles.isEmpty, "the same store remembers the warning")
    }

    @Test func quietRefreshDoesNotReassignDrives() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        let model = model(fixture, provider: UIFixture.Provider(volumes: fixture.volumes))
        await model.refresh()
        final class Flag: @unchecked Sendable { var changed = false }
        let flag = Flag()
        withObservationTracking { _ = model.drives } onChange: { flag.changed = true }
        await model.refresh(rescanning: [])
        #expect(!flag.changed)
    }
}

@Suite struct TrashSizeCacheTests {
    @Test func changedAndRemovedItemsAreMeasuredAgain() throws {
        let base = ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"] ?? NSTemporaryDirectory()
        let root = URL(fileURLWithPath: base).appendingPathComponent("sizecache/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 10_000).write(to: root.appendingPathComponent("Folder/one"))
        let scanner = TrashScanner()

        let first = scanner.scan(root: root)
        #expect(first.itemCount == 1)
        #expect(scanner.scan(root: root).totalBytes == first.totalBytes, "unchanged: same answer from the cache")

        try Data(repeating: 1, count: 200_000).write(to: root.appendingPathComponent("Folder/two"))
        #expect(scanner.scan(root: root).totalBytes > first.totalBytes, "a new child changes the folder's times")

        try FileManager.default.removeItem(at: root.appendingPathComponent("Folder"))
        #expect(scanner.scan(root: root).totalBytes == 0)
    }
}
