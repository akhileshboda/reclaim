import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// The real AppModel, driven headlessly against the throwaway RTEST-* disks: the same code the
/// buttons call, with the alert answered by a script. Runs only via `make test-integration`
/// (fresh fixtures, kernel sandbox).
@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["RECLAIM_INTEGRATION"] == "1"
    && ProcessInfo.processInfo.environment["RECLAIM_SANDBOXED"] == "1"), .serialized)
struct EndToEndIntegrationTests {
    let uid = getuid()

    func makeModel() -> (AppModel, ScriptedConfirmer) {
        let confirmer = ScriptedConfirmer(answer: true)
        return (AppModel(mode: .sandbox, settings: AppSettings(store: InMemorySettingsStore()), confirmer: confirmer), confirmer)
    }

    func drive(_ name: String, in model: AppModel) throws -> DriveState {
        try #require(model.drives.first { $0.drive.name == name }, "\(name) must be attached (Scripts/sandbox.sh up)")
    }

    @Test func emptyingTheSSDReclaimsSpaceAndKeepsEverythingElse() async throws {
        let (model, confirmer) = makeModel()
        await model.refresh()
        let before = try drive("RTEST-SSD", in: model)
        #expect(before.trash.itemCount == 7)
        let decoy = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"]!)
            .appendingPathComponent("decoy-outside-volume/must-survive.txt")

        await model.emptyTrash(driveID: before.id)

        let after = try drive("RTEST-SSD", in: model)
        let gained = after.drive.freeBytes - before.drive.freeBytes
        print("RTEST-SSD: trash \(ByteFormat.string(before.trash.totalBytes)) → \(ByteFormat.string(after.trash.totalBytes)); free \(ByteFormat.string(before.drive.freeBytes)) → \(ByteFormat.string(after.drive.freeBytes)) (+\(ByteFormat.string(gained)))")
        #expect(confirmer.requests.count == 1)
        #expect(after.trash.totalBytes == 0)
        #expect(try FileTree.children(of: before.trashURL!.path).isEmpty)
        #expect(gained >= 300_000_000)
        #expect(FileManager.default.fileExists(atPath: "/Volumes/RTEST-SSD/Keep/important.txt"))
        #expect(FileManager.default.fileExists(atPath: decoy.path), "the symlink target outside the volume survives")
        #expect(model.notice?.kind == .success)
    }

    @Test func emptyAllClearsEveryRemainingTrash() async throws {
        let (model, confirmer) = makeModel()
        await model.refresh()
        let reclaimable = model.totalReclaimable
        await model.emptyAllTrash()
        print("Empty All: reclaimed \(ByteFormat.string(reclaimable)) across \(confirmer.requests.first?.title ?? "")")
        #expect(model.totalReclaimable == 0)
        #expect(model.emptiableDrives.isEmpty)
    }

    @Test(arguments: ["RTEST-USB", "RTEST-CAM"])
    func junkCleanupOnNonMacFormats(_ name: String) async throws {
        let (model, _) = makeModel()
        await model.refresh()
        let state = try drive(name, in: model)
        let volume = state.drive.url.path

        func appleDoubleCount() -> Int {
            var count = 0
            FileTree.walk(volume) { entry in
                if entry.name.hasPrefix("._"), JunkScanner.fileCategory(of: URL(fileURLWithPath: entry.path)) == .appleDouble { count += 1 }
                return entry.level == 1 && entry.name == ".Trashes" ? .skipDescendants : .continue
            }
            return count
        }
        // Real sidecars written by the macOS kernel (not synthetic fixtures): a Finder tag on one
        // photo, only a download quarantine on another.
        let folder = name == "RTEST-USB" ? "/Photos/" : "/DCIM/100CANON/"
        let first = name == "RTEST-USB" ? "photo_1.jpg" : "IMG_1001.JPG", second = name == "RTEST-USB" ? "photo_2.jpg" : "IMG_1002.JPG"
        let tagged = volume + folder + first, quarantined = volume + folder + second
        let tags = try PropertyListSerialization.data(fromPropertyList: ["Red\n6"], format: .binary, options: 0)
        #expect(tags.withUnsafeBytes { setxattr(tagged, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, tags.count, 0, 0) } == 0)
        let quarantine = Data("0081;00000000;Safari;".utf8)
        #expect(quarantine.withUnsafeBytes { setxattr(quarantined, "com.apple.quarantine", $0.baseAddress, quarantine.count, 0, 0) } == 0)
        let taggedSidecar = try #require(AppleDouble.read(volume + folder + "._" + first), "the kernel wrote an AppleDouble sidecar")
        print("\(name): kernel-written ._\(first) attributes = \(taggedSidecar.attributeNames)")
        #expect(taggedSidecar.attributeNames.contains("com.apple.metadata:_kMDItemUserTags"))
        #expect(taggedSidecar.holdsUserMetadata)
        #expect(AppleDouble.read(volume + folder + "._" + second)?.holdsUserMetadata == false)

        let before = appleDoubleCount()
        #expect(before >= 20)

        await model.cleanJunk(driveID: state.id)

        #expect(Paths.exists(volume + folder + "._" + first), "the Finder tag survives cleanup")
        #expect(!Paths.exists(volume + folder + "._" + second))
        var keptTags = [UInt8](repeating: 0, count: 256)
        #expect(getxattr(tagged, "com.apple.metadata:_kMDItemUserTags", &keptTags, keptTags.count, 0, 0) > 0, "and still reads back as a tag")

        print("\(name): AppleDouble files \(before) → \(appleDoubleCount()); notice: \(model.notice?.text ?? "-")")
        #expect(appleDoubleCount() == 0)
        #expect(FileManager.default.fileExists(atPath: volume + "/Keep/important.txt"))
        if name == "RTEST-USB" {
            #expect(try FileTree.children(of: volume + "/Photos").contains("._notes-from-user.txt"), "decoy with a junk-like name survives")
            #expect(FileManager.default.fileExists(atPath: volume + "/Keep/.DS_Store"), "decoy .DS_Store without the Finder header survives")
            #expect(try FileTree.children(of: volume + "/Photos").filter { $0.hasSuffix(".jpg") && !$0.hasPrefix("._") }.count == 20)
        }
    }

    @Test func ejectAndReattach() async throws {
        let (model, _) = makeModel()
        await model.refresh()
        let hfs = try drive("RTEST-HFS", in: model)

        await model.eject(driveID: hfs.id)

        print("Eject: \(model.notice?.text ?? "-")")
        #expect(model.notice?.kind == .success)
        #expect(!model.drives.contains { $0.drive.name == "RTEST-HFS" })
        #expect(!FileManager.default.fileExists(atPath: "/Volumes/RTEST-HFS/Keep"))

        // Put the disk back for the next run.
        let image = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RECLAIM_SANDBOX_DIR"]!)
            .appendingPathComponent("images/RTEST-HFS.sparseimage").path
        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", "-quiet", "-noautoopen", image]
        try attach.run()
        attach.waitUntilExit()
        await model.refresh()
        #expect(model.drives.contains { $0.drive.name == "RTEST-HFS" }, "re-attached")
    }
}
