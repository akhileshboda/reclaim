import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// Fake volumes backed by real folders inside the test sandbox, so the real scanner, policy and
/// emptier run end to end.
final class UIFixture: @unchecked Sendable {
    let root: URL
    let volumes: URL
    let uid = getuid()

    init() throws {
        let base = ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"] ?? NSTemporaryDirectory()
        let dir = URL(fileURLWithPath: base).appendingPathComponent("ui/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: realpath(dir.path, nil).map { String(cString: $0) } ?? dir.path)
        volumes = root.appendingPathComponent("Volumes")
        try FileManager.default.createDirectory(at: volumes, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func addVolume(_ name: String, trashFiles: [String: Int]) throws -> URL {
        let volume = volumes.appendingPathComponent(name)
        let trash = volume.appendingPathComponent(".Trashes/\(uid)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        for (file, size) in trashFiles {
            let url = trash.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: size).write(to: url)
        }
        return volume
    }

    func trashContents(_ name: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: volumes.appendingPathComponent("\(name)/.Trashes/\(uid)").path)) ?? []
    }

    struct Provider: VolumeProviding {
        let volumes: URL
        func mountedDrives() -> [DriveInfo] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: volumes.path).sorted()) ?? []
            return names.map { name in
                DriveInfo(url: volumes.appendingPathComponent(name), name: name, totalBytes: 500_000_000_000,
                          freeBytes: 120_000_000_000, importantFreeBytes: 132_000_000_000, isEjectable: true)
            }
        }
    }

    @MainActor
    func model(confirm: Bool, ask: Bool = true) -> (AppModel, ScriptedConfirmer) {
        let confirmer = ScriptedConfirmer(answer: confirm)
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.askBeforeEmptying = ask
        let model = AppModel(
            mode: .sandbox,
            settings: settings,
            confirmer: confirmer,
            provider: Provider(volumes: volumes),
            locator: TrashLocator(mode: .sandbox, homeDirectory: root, userID: uid),
            policy: SafetyPolicy(mode: .sandbox, homeDirectory: root, volumesDirectory: volumes, userID: uid)
        )
        return (model, confirmer)
    }
}

@MainActor @Suite struct AppModelTests {
    @Test func refreshMeasuresEveryDrive() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 2_000_000, "b.txt": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: [:])
        let (model, _) = fixture.model(confirm: true)

        await model.refresh()

        #expect(model.hasLoaded)
        #expect(model.drives.map(\.drive.name) == ["RTEST-A", "RTEST-B"])
        #expect(model.drives[0].trash.itemCount == 2)
        #expect(model.drives[0].canEmpty)
        #expect(!model.drives[1].canEmpty)
        #expect(model.totalReclaimable >= 2_001_000)
        #expect(model.emptiableDrives.count == 1)
    }

    @Test func cancellingTheAlertDeletesNothing() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        let (model, confirmer) = fixture.model(confirm: false)
        await model.refresh()

        await model.emptyTrash(driveID: model.drives[0].id)

        #expect(confirmer.requests.count == 1)
        #expect(confirmer.requests[0].title.contains("“RTEST-A”"))
        #expect(confirmer.requests[0].message.contains("1 item"))
        #expect(fixture.trashContents("RTEST-A") == ["a.mov"])
        #expect(model.notice == nil)
    }

    @Test func confirmingEmptiesAndReports() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 3_000_000, "folder/b.bin": 1_000])
        let (model, _) = fixture.model(confirm: true)
        await model.refresh()

        await model.emptyTrash(driveID: model.drives[0].id)

        #expect(fixture.trashContents("RTEST-A").isEmpty)
        #expect(model.drives[0].trash.totalBytes == 0)
        #expect(model.notice?.kind == .success)
        #expect(model.notice?.text.hasPrefix("Reclaimed 3") == true)
        #expect(model.activity.isEmpty)
    }

    @Test func noQuestionWhenAskBeforeEmptyingIsOff() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        let (model, confirmer) = fixture.model(confirm: false, ask: false)
        await model.refresh()

        await model.emptyTrash(driveID: model.drives[0].id)

        #expect(confirmer.requests.isEmpty)
        #expect(fixture.trashContents("RTEST-A").isEmpty)
    }

    @Test func emptyAllAsksOnceWithTotals() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000, "b": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["c": 1_000])
        try fixture.addVolume("RTEST-C", trashFiles: [:])
        let (model, confirmer) = fixture.model(confirm: true)
        await model.refresh()

        await model.emptyAllTrash()

        #expect(confirmer.requests.count == 1)
        #expect(confirmer.requests[0].title.contains("2 drives"))
        #expect(confirmer.requests[0].message.hasPrefix("3 items"))
        #expect(fixture.trashContents("RTEST-A").isEmpty)
        #expect(fixture.trashContents("RTEST-B").isEmpty)
        #expect(model.notice?.text.contains("on 2 drives") == true)
    }

    @Test func deleteItemsRemovesOnlyTheSelection() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["big.mov": 2_000_000, "keep.txt": 1_000])
        let (model, confirmer) = fixture.model(confirm: true)
        await model.refresh()
        let big = try #require(model.drives[0].trash.largestItems.first { $0.name == "big.mov" })

        await model.deleteItems([big], driveID: model.drives[0].id)

        #expect(confirmer.requests.first?.title.contains("“big.mov”") == true)
        #expect(fixture.trashContents("RTEST-A") == ["keep.txt"])
    }

    @Test func badgeFollowsSettings() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a": 10_000])
        let (model, _) = fixture.model(confirm: true)
        await model.refresh()

        #expect(model.badgeText == nil, "automatic mode hides small amounts")
        model.settings.badgeMode = .always
        #expect(model.badgeText != nil)
        model.settings.badgeMode = .iconOnly
        #expect(model.badgeText == nil)
    }
}

@Suite struct BadgeModeTests {
    @Test func automaticThreshold() {
        #expect(BadgeMode.automatic.text(reclaimable: 999_999_999) == nil)
        #expect(BadgeMode.automatic.text(reclaimable: 1_000_000_000) == "1.0 GB")
        #expect(BadgeMode.always.text(reclaimable: 0) == "0.0 KB")
        #expect(BadgeMode.iconOnly.text(reclaimable: 50_000_000_000) == nil)
    }
}
