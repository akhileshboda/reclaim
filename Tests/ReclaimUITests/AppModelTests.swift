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
        // FileTree, not FileManager: FileManager hides "._" files and would make "empty" a lie.
        (try? FileTree.children(of: volumes.appendingPathComponent("\(name)/.Trashes/\(uid)").path).sorted()) ?? []
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

    final class FakeEjector: DriveEjecting, @unchecked Sendable {
        var ejected: [URL] = []
        var error: (any Error)?
        func eject(_ volume: URL) throws {
            if let error { throw error }
            ejected.append(volume)
        }
    }

    @MainActor
    func model(confirm: Bool, ask: Bool = true, ejector: FakeEjector = FakeEjector()) -> (AppModel, ScriptedConfirmer) {
        let confirmer = ScriptedConfirmer(answer: confirm)
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.askBeforeEmptying = ask
        let model = AppModel(
            mode: .sandbox,
            settings: settings,
            confirmer: confirmer,
            provider: Provider(volumes: volumes),
            locator: TrashLocator(mode: .sandbox, homeDirectory: root, userID: uid),
            policy: SafetyPolicy(mode: .sandbox, homeDirectory: root, volumesDirectory: volumes, userID: uid),
            ejector: ejector
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

@MainActor @Suite struct EjectAndJunkModelTests {
    @Test func ejectCallsTheEjectorAndReports() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        let ejector = UIFixture.FakeEjector()
        let (model, _) = fixture.model(confirm: true, ejector: ejector)
        await model.refresh()

        await model.eject(driveID: model.drives[0].id)

        #expect(ejector.ejected.map(\.lastPathComponent) == ["RTEST-A"])
        #expect(model.notice?.kind == .success)
    }

    @Test func ejectFailureIsExplained() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        let ejector = UIFixture.FakeEjector()
        ejector.error = CocoaError(.fileWriteVolumeReadOnly)
        let (model, _) = fixture.model(confirm: true, ejector: ejector)
        await model.refresh()

        await model.eject(driveID: model.drives[0].id)

        #expect(model.notice?.kind == .warning)
        #expect(model.notice?.text.contains("couldn’t be ejected") == true)
    }

    @Test func junkFlowAsksThenRemovesOnlyJunk() async throws {
        let fixture = try UIFixture()
        let volume = try fixture.addVolume("RTEST-A", trashFiles: [:])
        try Data([0, 0, 0, 1] + Array("Bud1".utf8) + [UInt8](repeating: 0, count: 100)).write(to: volume.appendingPathComponent(".DS_Store"))
        try Data([0, 5, 0x16, 7] + [UInt8](repeating: 0, count: 100)).write(to: volume.appendingPathComponent("._song.mp3"))
        try Data("mine".utf8).write(to: volume.appendingPathComponent("._mine.txt"))
        let (model, confirmer) = fixture.model(confirm: true)
        await model.refresh()

        await model.cleanJunk(driveID: model.drives[0].id)

        #expect(confirmer.requests.first?.message.hasPrefix("2 files") == true)
        let left = try FileTree.children(of: volume.path)
        #expect(!left.contains(".DS_Store"))
        #expect(!left.contains("._song.mp3"))
        #expect(left.contains("._mine.txt"))
        #expect(model.notice?.text.contains("Removed 2 hidden files") == true)
    }

    @Test func junkFlowReportsWhenThereIsNothing() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        let (model, confirmer) = fixture.model(confirm: true)
        await model.refresh()

        await model.cleanJunk(driveID: model.drives[0].id)

        #expect(confirmer.requests.isEmpty)
        #expect(model.notice?.text.hasPrefix("No hidden macOS files") == true)
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

@MainActor @Suite struct SettingsAndShortcutTests {
    @Test func shortcutDisplayAndCarbonMask() {
        let shortcut = Shortcut.defaultOpenPanel
        #expect(shortcut.displayString == "⌃⌥⌘R")
        #expect(shortcut.accessibilityLabel == "Control Option Command R")
        #expect(shortcut.carbonModifiers == 0x1000 | 0x0800 | 0x0100)
    }

    @Test func globalShortcutsCantHijackStandardOnes() {
        #expect(Shortcut.problem(modifiers: [.command], key: "c") != nil, "⌘C is Copy")
        #expect(Shortcut.problem(modifiers: [.command], key: "q") != nil, "⌘Q is Quit")
        #expect(Shortcut.problem(modifiers: [.option], key: "e") != nil, "⌥E types an accent")
        #expect(Shortcut.problem(modifiers: [.command, .shift], key: "4") != nil, "⇧ doesn't count")
        #expect(Shortcut.problem(modifiers: [.control, .command], key: "q")?.contains("Lock Screen") == true)
        #expect(Shortcut.problem(modifiers: [.control, .option, .command], key: "r") == nil)
        #expect(Shortcut.problem(modifiers: [.control, .option], key: "space") == nil)
    }

    @Test func settingsPersistAndDefaults() {
        let store = InMemorySettingsStore()
        let first = AppSettings(store: store)
        #expect(first.askBeforeEmptying)
        #expect(first.badgeMode == .automatic)
        #expect(first.openPanelShortcut == .defaultOpenPanel)
        first.askBeforeEmptying = false
        first.badgeMode = .always
        first.lowSpacePercent = 20
        first.openPanelShortcut = nil

        let second = AppSettings(store: store)
        #expect(!second.askBeforeEmptying)
        #expect(second.badgeMode == .always)
        #expect(second.lowSpacePercent == 20)
        #expect(second.openPanelShortcut == nil, "a removed shortcut stays removed")
    }

    final class RecordingNotifier: LowSpaceNotifying {
        var messages: [String] = []
        func notify(driveID: String, title: String, body: String) { messages.append(title + " | " + body) }
    }

    @Test func lowSpaceNotifiesOncePerDrive() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        let (model, _) = fixture.model(confirm: true)
        let notifier = RecordingNotifier()
        model.lowSpaceNotifier = notifier
        model.settings.lowSpacePercent = 30 // fixture drives have 26.4% available

        await model.refresh()
        await model.refresh()

        #expect(notifier.messages.count == 1)
        #expect(notifier.messages[0].hasPrefix("“RTEST-A” Is Almost Full"))

    }

    /// A fresh model, so the once-per-day limiter can't be what keeps it quiet.
    @Test func noLowSpaceAlertsWhenTurnedOff() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        let (model, _) = fixture.model(confirm: true)
        let notifier = RecordingNotifier()
        model.lowSpaceNotifier = notifier
        model.settings.lowSpaceAlerts = false
        model.settings.lowSpacePercent = 50 // well above the fixture's 26.4% available

        await model.refresh()

        #expect(notifier.messages.isEmpty)
    }
}

/// Counts scans so tests can prove which Trash folders were (not) touched.
final class CountingScanner: TrashScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func scan(root: URL, largestCount: Int) -> TrashSummary {
        lock.withLock { counts[root.path, default: 0] += 1 }
        return TrashScanner().scan(root: root, largestCount: largestCount)
    }
    func count(containing fragment: String) -> Int {
        lock.withLock { counts.filter { $0.key.contains(fragment) }.values.reduce(0, +) }
    }
}

@MainActor @Suite struct PartialRefreshTests {
    func model(_ fixture: UIFixture, scanner: CountingScanner) -> AppModel {
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

    @Test func capacityOnlyRefreshDoesNotTouchTrashFolders() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["b": 1_000])
        let scanner = CountingScanner()
        let model = model(fixture, scanner: scanner)
        await model.refresh()
        #expect(scanner.count(containing: "RTEST-A") == 1)

        await model.refresh(rescanning: [])
        await model.refresh(rescanning: [])

        #expect(scanner.count(containing: "RTEST-A") == 1, "no rescans: a sleeping disk stays asleep")
        #expect(scanner.count(containing: "RTEST-B") == 1)
        #expect(model.drives[0].trash.itemCount == 1, "last measurement kept")
    }

    @Test func rescansOnlyTheChangedDrive() async throws {
        let fixture = try UIFixture()
        let a = try fixture.addVolume("RTEST-A", trashFiles: ["a": 1_000])
        try fixture.addVolume("RTEST-B", trashFiles: ["b": 1_000])
        let scanner = CountingScanner()
        let model = model(fixture, scanner: scanner)
        await model.refresh()

        try Data(count: 5_000).write(to: a.appendingPathComponent(".Trashes/\(fixture.uid)/new.bin"))
        let changed = model.driveIDs(containing: [a.appendingPathComponent(".Trashes/\(fixture.uid)/new.bin").path])
        await model.refresh(rescanning: changed)

        #expect(changed == [a.path])
        #expect(scanner.count(containing: "RTEST-A") == 2)
        #expect(scanner.count(containing: "RTEST-B") == 1)
        #expect(model.drives[0].trash.itemCount == 2)
    }

    @Test func newDrivesAreAlwaysScanned() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: [:])
        let scanner = CountingScanner()
        let model = model(fixture, scanner: scanner)
        await model.refresh()
        try fixture.addVolume("RTEST-NEW", trashFiles: ["x": 1_000])

        await model.refresh(rescanning: [])

        #expect(model.drives.first { $0.drive.name == "RTEST-NEW" }?.trash.itemCount == 1)
    }

    @Test func mergeRules() {
        #expect(AppModel.merge([], ["a"]) == ["a"])
        #expect(AppModel.merge(["a"], ["b"]) == ["a", "b"])
        #expect(AppModel.merge(nil, ["a"]) == nil)
        #expect(AppModel.merge(["a"], nil) == nil)
    }
}
