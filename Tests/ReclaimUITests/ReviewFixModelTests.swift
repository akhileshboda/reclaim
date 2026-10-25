import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

@MainActor @Suite struct ReviewFixModelTests {
    /// A provider whose drive identity can change, like a different disk with the same name.
    final class SwappableProvider: VolumeProviding, @unchecked Sendable {
        let volumes: URL
        private let lock = NSLock()
        private var uuid = "UUID-ORIGINAL"
        init(volumes: URL) { self.volumes = volumes }
        func swapDisk() { lock.withLock { uuid = "UUID-OTHER-DISK" } }
        func mountedDrives() -> [DriveInfo] {
            let id = lock.withLock { uuid }
            return [DriveInfo(url: volumes.appendingPathComponent("RTEST-A"), name: "RTEST-A", totalBytes: 1_000_000_000,
                              freeBytes: 500_000_000, isEjectable: true, uuid: id)]
        }
    }

    func model(_ fixture: UIFixture, provider: any VolumeProviding, confirmer: ScriptedConfirmer, ask: Bool = true) -> AppModel {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.askBeforeEmptying = ask
        return AppModel(
            mode: .sandbox, settings: settings, confirmer: confirmer, provider: provider,
            locator: TrashLocator(mode: .sandbox, homeDirectory: fixture.root, userID: fixture.uid),
            policy: SafetyPolicy(mode: .sandbox, homeDirectory: fixture.root, volumesDirectory: fixture.volumes, userID: fixture.uid)
        )
    }

    @Test func driveSwappedWhileTheAlertIsUpIsNotEmptied() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        let provider = SwappableProvider(volumes: fixture.volumes)
        let confirmer = ScriptedConfirmer(answer: true)
        let model = model(fixture, provider: provider, confirmer: confirmer)
        await model.refresh()
        // While the alert is up, a different disk with the same name is mounted at the same path.
        confirmer.whileAsking = {
            provider.swapDisk()
            await model.refresh()
        }

        await model.emptyTrash(driveID: model.drives[0].id)

        #expect(fixture.trashContents("RTEST-A") == ["a.mov"], "nothing erased on a disk the person didn't confirm")
        #expect(model.notice?.text == "“RTEST-A” changed while Reclaim was asking. Nothing was erased.")
    }

    @Test func unchangedDriveIsEmptiedAfterTheAlert() async throws {
        let fixture = try UIFixture()
        try fixture.addVolume("RTEST-A", trashFiles: ["a.mov": 1_000])
        let provider = SwappableProvider(volumes: fixture.volumes)
        let confirmer = ScriptedConfirmer(answer: true)
        let model = model(fixture, provider: provider, confirmer: confirmer)
        await model.refresh()
        confirmer.whileAsking = { await model.refresh() } // a refresh that changes nothing

        await model.emptyTrash(driveID: model.drives[0].id)

        #expect(fixture.trashContents("RTEST-A").isEmpty)
    }

    @Test func eraseImmediatelyAlwaysAsksAndTakesItsCompanion() async throws {
        let fixture = try UIFixture()
        let volume = try fixture.addVolume("RTEST-A", trashFiles: ["clip.mov": 2_000, "._clip.mov": 100, "keep.txt": 10])
        let confirmer = ScriptedConfirmer(answer: true)
        let model = model(fixture, provider: UIFixture.Provider(volumes: fixture.volumes), confirmer: confirmer, ask: false)
        await model.refresh()
        #expect(model.drives[0].trash.itemCount == 2, "the companion isn't listed")
        let clip = try #require(model.drives[0].trash.largestItems.first { $0.name == "clip.mov" })

        await model.deleteItems([clip], driveID: model.drives[0].id)

        #expect(confirmer.requests.count == 1, "Erase Immediately asks even with 'Ask before emptying' off")
        #expect(confirmer.requests[0].title == "Erase “clip.mov” immediately?")
        #expect(fixture.trashContents("RTEST-A") == ["keep.txt"], "._clip.mov went with clip.mov")
        _ = volume
    }

    @Test func alertsAreShortAndNotDestructiveStyled() {
        let request = ConfirmationRequest.emptyTrash(driveName: "Footage SSD", itemCount: 214, bytes: 186_400_000_000)
        #expect(request.title == "Empty the Trash on “Footage SSD”?")
        #expect(request.message.hasPrefix("214 items (186.4 GB) will be permanently erased."))
        #expect(!request.isDestructive, "the person chose Empty Trash; HIG: no destructive style for the chosen action")
        let all = ConfirmationRequest.emptyAllTrash(driveNames: ["Footage SSD", "KINGSTON"], itemCount: 3, bytes: 1_000)
        #expect(all.message.contains("“Footage SSD” and “KINGSTON”"))
    }

    @Test func errorsReadAsPlainLanguage() {
        let violation = UserMessage.describe(SafetyPolicy.Violation.symlinkInPath("/Volumes/X/.Trashes/501"), driveName: "X")
        #expect(!violation.contains("/Volumes"), "no raw paths on screen")
        #expect(violation.contains("Nothing was erased"))
        let unreadable = UserMessage.describe(JunkScanner.ScanError.unreadable(EACCES), driveName: "USB")
        #expect(unreadable.contains("Privacy & Security"))
    }
}
