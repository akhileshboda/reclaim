import Foundation
import Testing
@testable import ReclaimCore

@Suite struct TrashLocatorTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    @Test func bootDriveUsesHomeTrashInLiveMode() {
        let boot = DriveInfo(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalBytes: 1, freeBytes: 0, isBoot: true)
        let locator = TrashLocator(mode: .live, homeDirectory: home, userID: 501)
        #expect(locator.trashURL(for: boot)?.path == "/Users/someone/.Trash")
    }

    @Test func bootDriveTrashIsHiddenInSandboxMode() {
        let boot = DriveInfo(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalBytes: 1, freeBytes: 0, isBoot: true)
        #expect(TrashLocator(mode: .sandbox, homeDirectory: home, userID: 501).trashURL(for: boot) == nil)
    }

    @Test func externalDriveUsesPerUserTrashes() {
        let drive = DriveInfo(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup", totalBytes: 1, freeBytes: 0)
        let locator = TrashLocator(mode: .live, homeDirectory: home, userID: 501)
        #expect(locator.trashURL(for: drive)?.path == "/Volumes/Backup/.Trashes/501")
    }
}

@Suite struct TrashScannerTests {
    @Test func measuresItemsAndOrdersLargestFirst() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(trash.appendingPathComponent("small.txt"), bytes: 10_000)
        try fixture.write(trash.appendingPathComponent("big.mov"), bytes: 3_000_000)
        try fixture.write(trash.appendingPathComponent("Folder/a.bin"), bytes: 500_000)
        try fixture.write(trash.appendingPathComponent("Folder/Nested/b.bin"), bytes: 500_000)
        try fixture.write(trash.appendingPathComponent(".DS_Store"), bytes: 6_000)

        let summary = TrashScanner().scan(root: trash, largestCount: 2)
        #expect(summary.access == .readable)
        #expect(summary.itemCount == 3)
        #expect(summary.largestItems.map(\.name) == ["big.mov", "Folder"])
        #expect(summary.largestItems[1].isDirectory)
        #expect(summary.totalBytes >= 4_016_000 && summary.totalBytes < 4_100_000, "allocated size, counted once")
        #expect(summary.largestItems[0].bytes >= 3_000_000 && summary.largestItems[0].bytes < 3_010_000)
    }

    @Test func doesNotFollowSymlinks() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(fixture.outside.appendingPathComponent("huge.bin"), bytes: 5_000_000)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link"), withDestinationURL: fixture.outside)
        let summary = TrashScanner().scan(root: trash)
        #expect(summary.itemCount == 1)
        #expect(summary.totalBytes == 0)
    }

    @Test func missingTrashIsEmpty() throws {
        let fixture = try Fixture()
        let summary = TrashScanner().scan(root: fixture.root.appendingPathComponent("nope"))
        #expect(summary == .empty)
    }
}

@Suite struct TrashEmptierTests {
    @Test func emptiesEverythingIncludingLockedAndReadOnlyItems() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(trash.appendingPathComponent("movie.mov"), bytes: 1_000_000)
        let locked = try fixture.write(trash.appendingPathComponent("locked.pdf"), bytes: 1_000)
        #expect(chflags(locked.path, UInt32(UF_IMMUTABLE)) == 0)
        let readOnlyDir = trash.appendingPathComponent("Read-only")
        try fixture.write(readOnlyDir.appendingPathComponent("inner.txt"), bytes: 1_000)
        #expect(chmod(readOnlyDir.path, 0o555) == 0)
        let lockedInside = try fixture.write(trash.appendingPathComponent("Folder/locked-inside.txt"), bytes: 1_000)
        #expect(chflags(lockedInside.path, UInt32(UF_IMMUTABLE)) == 0)

        let result = try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash)

        #expect(result.failures.isEmpty)
        #expect(result.removedCount == 4)
        #expect(result.freedBytes >= 1_003_000 && result.freedBytes < 1_100_000)
        #expect(try FileTree.children(of: trash.path).isEmpty)
        #expect(fixture.exists(trash), "the trash folder itself stays")
    }

    @Test func symlinkEscapeDeletesOnlyTheLink() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let precious = try fixture.write(fixture.outside.appendingPathComponent("precious.txt"), bytes: 100)
        let keep = try fixture.write(fixture.volumes.appendingPathComponent("RTEST-UNIT/Keep/important.txt"), bytes: 100)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link to outside"), withDestinationURL: fixture.outside)
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link to keep"), withDestinationURL: keep.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: trash.appendingPathComponent("link to file"), withDestinationURL: precious)

        let result = try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash)

        #expect(result.removedCount == 3)
        #expect(fixture.exists(precious))
        #expect(fixture.exists(keep))
        #expect(fixture.exists(fixture.outside))
        #expect(try FileTree.children(of: trash.path).isEmpty)
    }

    @Test func refusesNonTrashRootsWithoutDeletingAnything() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-UNIT")
        let file = try fixture.write(volume.appendingPathComponent("Keep/important.txt"), bytes: 100)
        let emptier = TrashEmptier(policy: fixture.policy())
        for root in [volume, volume.appendingPathComponent("Keep"), fixture.home, fixture.root] {
            #expect(throws: SafetyPolicy.Violation.self) { try emptier.emptyTrash(at: root) }
        }
        #expect(fixture.exists(file))
    }

    @Test func removeItemsValidatesEverythingFirst() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let a = try fixture.write(trash.appendingPathComponent("a.bin"), bytes: 100)
        let outsider = try fixture.write(fixture.outside.appendingPathComponent("b.bin"), bytes: 100)
        let emptier = TrashEmptier(policy: fixture.policy())

        #expect(throws: SafetyPolicy.Violation.self) { try emptier.removeItems([a, outsider], fromTrashAt: trash) }
        #expect(fixture.exists(a), "nothing is deleted when any item is invalid")
        #expect(fixture.exists(outsider))

        let result = try emptier.removeItems([a], fromTrashAt: trash)
        #expect(result.removedCount == 1)
        #expect(!fixture.exists(a))
    }

    @Test func reportsFailuresAndKeepsGoing() throws {
        struct FailingRemover: FileRemoving {
            let failingName: String
            func removeItem(atPath path: String) throws {
                if path.hasSuffix(failingName) { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.removeItem(atPath: path)
            }
        }
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(trash.appendingPathComponent("ok.bin"), bytes: 100)
        let stuck = try fixture.write(trash.appendingPathComponent("stuck.bin"), bytes: 100)

        let result = try TrashEmptier(policy: fixture.policy(), remover: FailingRemover(failingName: "stuck.bin")).emptyTrash(at: trash)
        #expect(result.removedCount == 1)
        #expect(result.failures.map(\.url.lastPathComponent) == ["stuck.bin"])
        #expect(fixture.exists(stuck))
    }
}

@Suite struct VolumeProviderTests {
    @Test func liveModeShowsBootAndVolumes() {
        #expect(VolumeProvider.isUserFacing(path: "/", mode: .live))
        #expect(VolumeProvider.isUserFacing(path: "/Volumes/Backup", mode: .live))
        #expect(!VolumeProvider.isUserFacing(path: "/System/Volumes/Data", mode: .live))
        #expect(!VolumeProvider.isUserFacing(path: "/Volumes/Backup/nested", mode: .live))
    }

    @Test func sandboxModeShowsOnlyTestVolumes() {
        #expect(!VolumeProvider.isUserFacing(path: "/", mode: .sandbox))
        #expect(!VolumeProvider.isUserFacing(path: "/Volumes/Backup", mode: .sandbox))
        #expect(VolumeProvider.isUserFacing(path: "/Volumes/RTEST-SSD", mode: .sandbox))
    }

    @Test func bootFirstThenInternalThenExternalAlphabetical() {
        func drive(_ name: String, boot: Bool = false, isInternal: Bool = false) -> DriveInfo {
            DriveInfo(url: URL(fileURLWithPath: "/Volumes/\(name)"), name: name, totalBytes: 1, freeBytes: 0, isBoot: boot, isInternal: isInternal)
        }
        let sorted = [drive("Zed"), drive("alpha"), drive("Macintosh HD", boot: true, isInternal: true), drive("Data2", isInternal: true)]
            .sorted(by: VolumeProvider.displayOrder)
        #expect(sorted.map(\.name) == ["Macintosh HD", "Data2", "alpha", "Zed"])
    }
}
