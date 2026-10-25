import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

@MainActor @Suite struct RefreshAndWatcherTests {
    func model(_ fixture: UIFixture, scanner: CountingScanner = CountingScanner()) -> AppModel {
        AppModel(
            mode: .sandbox,
            settings: AppSettings(store: InMemorySettingsStore()),
            confirmer: ScriptedConfirmer(answer: true),
            provider: UIFixture.Provider(volumes: fixture.volumes),
            locator: TrashLocator(mode: .sandbox, homeDirectory: fixture.root, userID: fixture.uid),
            scanner: scanner,
            policy: SafetyPolicy(mode: .sandbox, homeDirectory: fixture.root, volumesDirectory: fixture.volumes, userID: fixture.uid)
        )
    }

    @Test func overlappingRefreshesAreMergedNotLost() async throws {
        let fixture = try UIFixture()
        let a = try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["b": 1_000])
        let scanner = CountingScanner()
        let model = model(fixture, scanner: scanner)
        await model.refresh()

        try Data(count: 10).write(to: a.appendingPathComponent(".Trashes/\(fixture.uid)/new"))
        let first = Task { await model.refresh(rescanning: []) }
        await Task.yield()
        await model.refresh(rescanning: [a.path]) // arrives while the first may still be running
        await first.value

        #expect(scanner.count(containing: "RTEST-A") == 2, "the queued rescan of A happened")
        #expect(scanner.count(containing: "RTEST-B") == 1)
        #expect(model.state(for: a.path)?.trash.itemCount == 2)
        #expect(!model.isRefreshing)
    }

    @Test func driveWithoutATrashFolderIsWatchedAtItsRoot() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        let fresh = fixture.volumes.appendingPathComponent("RTEST-NEW")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true) // no .Trashes yet
        let model = model(fixture)
        await model.refresh()

        let trashA = fixture.volumes.appendingPathComponent("RTEST-A/.Trashes/\(fixture.uid)").path
        #expect(Set(model.watchableTrashPaths) == [trashA, fresh.path])

        // FSEvents reports the parent folder, often with a trailing slash, when .Trashes appears.
        #expect(model.driveIDs(containing: [fresh.path + "/.Trashes/"]) == [fresh.path])
        #expect(model.driveIDs(containing: [trashA + "/"]) == [fixture.volumes.appendingPathComponent("RTEST-A").path])
        #expect(model.driveIDs(containing: [fixture.volumes.appendingPathComponent("RTEST-A/Photos").path]).isEmpty,
                "changes outside a readable Trash don't trigger rescans")
        #expect(model.unwatchedDriveIDs.isEmpty)
    }
}
