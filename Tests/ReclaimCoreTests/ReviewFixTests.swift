import Foundation
import Testing
@testable import ReclaimCore

/// Builds AppleDouble sidecars the way macOS lays them out: header, entries, FinderInfo with an
/// optional "ATTR" block of extended attribute names, optional resource fork.
func makeAppleDouble(attributes: [String] = [], resourceFork: Int = 0, emptyFork: Bool = false, finderInfo: [UInt8] = Array(repeating: 0, count: 32)) -> [UInt8] {
    func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }

    var attrBlock: [UInt8] = []
    if !attributes.isEmpty {
        var entries: [UInt8] = []
        for name in attributes {
            let nameBytes = Array(name.utf8) + [0]
            var entry = be32(0) + be32(0) + be16(0) + [UInt8(nameBytes.count)] + nameBytes
            while entry.count % 4 != 0 { entry.append(0) }
            entries += entry
        }
        attrBlock = Array("ATTR".utf8) + be32(0) + be32(0) + be32(0) + be32(0) + Array(repeating: 0, count: 12) + be16(0) + be16(attributes.count) + entries
    }
    let entryCount = resourceFork > 0 || emptyFork ? 2 : 1
    let finderInfoOffset = 26 + entryCount * 12
    let finderInfoLength = 32 + (attrBlock.isEmpty ? 0 : 2 + attrBlock.count)
    var bytes: [UInt8] = [0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00] + Array(repeating: 0, count: 16) + be16(entryCount)
    bytes += be32(9) + be32(finderInfoOffset) + be32(finderInfoLength)
    // A resource fork laid out like the real thing: 256-byte header area, `resourceFork` bytes of
    // data, then a 30-byte map. `resourceFork == 0` with `emptyFork` gives the 286-byte empty
    // fork macOS writes into every sidecar.
    // Built step by step: as one expression, Swift 6.0 compilers time out type-checking it.
    var forkBytes: [UInt8] = []
    if resourceFork > 0 || emptyFork {
        forkBytes += be32(256)
        forkBytes += be32(256 + resourceFork)
        forkBytes += be32(resourceFork)
        forkBytes += be32(30)
        forkBytes += [UInt8](repeating: 0, count: 240)
        forkBytes += [UInt8](repeating: 0xAB, count: resourceFork)
        forkBytes += [UInt8](repeating: 0, count: 30)
    }
    if !forkBytes.isEmpty { bytes += be32(2) + be32(finderInfoOffset + finderInfoLength) + be32(forkBytes.count) }
    bytes += finderInfo + (attrBlock.isEmpty ? [] : [0, 0] + attrBlock)
    bytes += forkBytes
    return bytes
}

@Suite struct AppleDoubleTests {
    @Test func disposableBookkeepingIsNotUserMetadata() throws {
        let contents = try #require(AppleDouble.parse(makeAppleDouble(attributes: ["com.apple.quarantine", "com.apple.provenance"])))
        #expect(contents.attributeNames == ["com.apple.quarantine", "com.apple.provenance"])
        #expect(!contents.holdsUserMetadata)
    }

    @Test func tagsCommentsForksLabelsAndUnknownsAreKept() throws {
        let tags = try #require(AppleDouble.parse(makeAppleDouble(attributes: ["com.apple.quarantine", "com.apple.metadata:_kMDItemUserTags"])))
        #expect(tags.holdsUserMetadata)
        #expect(try #require(AppleDouble.parse(makeAppleDouble(attributes: ["com.apple.metadata:kMDItemFinderComment"]))).holdsUserMetadata)
        #expect(try #require(AppleDouble.parse(makeAppleDouble(attributes: ["com.example.unknown"]))).holdsUserMetadata, "unknown means keep")
        let fork = try #require(AppleDouble.parse(makeAppleDouble(resourceFork: 512)))
        #expect(fork.resourceForkLength == 512)
        #expect(fork.holdsUserMetadata)
        // Regression: macOS puts an empty 286-byte fork in every sidecar; it must not count.
        let empty = try #require(AppleDouble.parse(makeAppleDouble(attributes: ["com.apple.quarantine"], emptyFork: true)))
        #expect(empty.resourceForkLength == 0)
        #expect(!empty.holdsUserMetadata)
        var labelled = [UInt8](repeating: 0, count: 32)
        labelled[9] = 0x0C // fdFlags colour bits = 6 (red)
        #expect(try #require(AppleDouble.parse(makeAppleDouble(finderInfo: labelled))).holdsUserMetadata)
    }

    @Test func emptyHeaderAndGarbage() {
        #expect(AppleDouble.parse([0x00, 0x05, 0x16, 0x07] + [UInt8](repeating: 0, count: 4092))?.holdsUserMetadata == false)
        #expect(AppleDouble.parse(Array("not an appledouble".utf8)) == nil)
        #expect(AppleDouble.parse([0x00, 0x05, 0x16, 0x07, 0, 2, 0, 0]) == nil, "truncated header")
    }

    @Test func scannerKeepsSidecarsWithMetadataButRemovesOrphans() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        try fixture.write(volume.appendingPathComponent("clip.mov"), bytes: 1_000)
        try Data(makeAppleDouble(attributes: ["com.apple.metadata:_kMDItemUserTags"])).write(to: volume.appendingPathComponent("._clip.mov"))
        try fixture.write(volume.appendingPathComponent("song.mp3"), bytes: 1_000)
        try Data(makeAppleDouble(attributes: ["com.apple.quarantine"])).write(to: volume.appendingPathComponent("._song.mp3"))
        try Data(makeAppleDouble(attributes: ["com.apple.metadata:_kMDItemUserTags"])).write(to: volume.appendingPathComponent("._gone.mov"))

        let report = try JunkScanner(policy: fixture.policy()).scan(volume: volume)
        let byName = Dictionary(uniqueKeysWithValues: report.items.map { ($0.url.lastPathComponent, $0.category) })
        #expect(byName["._clip.mov"] == .appleDoubleWithMetadata)
        #expect(byName["._song.mp3"] == .appleDouble)
        #expect(byName["._gone.mov"] == .appleDouble, "an orphan's metadata belongs to nothing")

        _ = try JunkCleaner(policy: fixture.policy()).clean(report.filtered(to: JunkReport.defaultCategories))
        #expect(fixture.exists(volume.appendingPathComponent("._clip.mov")), "Finder tags survive cleanup")
        #expect(!fixture.exists(volume.appendingPathComponent("._song.mp3")))
        #expect(!fixture.exists(volume.appendingPathComponent("._gone.mov")))
    }
}

@Suite struct ReviewFixTests {
    @Test func walkReportsUnreadableFolders() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        let locked = volume.appendingPathComponent("Private")
        try fixture.write(locked.appendingPathComponent("._x"), bytes: 10)
        #expect(chmod(locked.path, 0o000) == 0)
        defer { chmod(locked.path, 0o755) }

        var errors: [String] = []
        FileTree.walk(volume.path, onError: { path, _ in errors.append(path) }) { _ in .continue }
        #expect(errors.contains { $0.hasSuffix("/Private") })
        #expect(try JunkScanner(policy: fixture.policy()).scan(volume: volume).unreadableFolders == 1)
    }

    @Test func unreadableVolumeIsAnErrorNotAnEmptyReport() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        #expect(chmod(volume.path, 0o000) == 0)
        defer { chmod(volume.path, 0o755) }
        #expect(throws: JunkScanner.ScanError.self) { try JunkScanner(policy: fixture.policy()).scan(volume: volume) }
    }

    @Test func unlistableTrashThrowsInsteadOfReportingSuccess() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(trash.appendingPathComponent("a.bin"), bytes: 10)
        #expect(chmod(trash.path, 0o000) == 0)
        defer { chmod(trash.path, 0o700) }
        #expect(throws: POSIXError.self) { try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash) }
    }

    @Test func hardLinkToALockedFileOutsideStaysLocked() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let original = try fixture.write(fixture.volumes.appendingPathComponent("RTEST-UNIT/Keep/contract.pdf"), bytes: 100)
        // Link first: macOS refuses to hard-link a file that's already locked.
        #expect(link(original.path, trash.appendingPathComponent("contract.pdf").path) == 0)
        #expect(chflags(original.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(original.path, 0) }

        let result = try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash)

        var info = stat()
        #expect(lstat(original.path, &info) == 0)
        #expect(info.st_flags & UInt32(UF_IMMUTABLE) != 0, "Reclaim must not unlock a file outside the Trash")
        #expect(result.failures.count == 1, "the locked link is reported, not silently forced")
    }

    @Test func hardLinkedBlocksAreCountedOnce() throws {
        let fixture = try Fixture()
        let folder = fixture.root.appendingPathComponent("linked")
        let a = try fixture.write(folder.appendingPathComponent("a.bin"), bytes: 1_000_000)
        #expect(link(a.path, folder.appendingPathComponent("b.bin").path) == 0)
        let size = FileTree.allocatedSize(of: folder.path)
        #expect(size >= 1_000_000 && size < 2_000_000)
    }

    @Test func swappedTrashFolderStopsTheEmptying() throws {
        /// Deletes the first item, then swaps the Trash folder for a different one (as a concurrent
        /// writer could), and records everything it was asked to delete afterwards.
        final class SwappingRemover: FileRemoving, @unchecked Sendable {
            let root: URL
            var calls: [String] = []
            init(root: URL) { self.root = root }
            func removeItem(atPath path: String) throws {
                calls.append(path)
                try FileManager.default.removeItem(atPath: path)
                if calls.count == 1 {
                    try FileManager.default.moveItem(at: root, to: root.deletingLastPathComponent().appendingPathComponent("moved"))
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                }
            }
        }
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        for name in ["a", "b", "c"] { try fixture.write(trash.appendingPathComponent(name), bytes: 10) }
        let remover = SwappingRemover(root: trash)

        let result = try TrashEmptier(policy: fixture.policy(), remover: remover).emptyTrash(at: trash)

        #expect(remover.calls.count == 1)
        #expect(result.failures.count == 2)
        #expect(try FileTree.children(of: trash.deletingLastPathComponent().appendingPathComponent("moved").path).count == 2,
                "the moved folder's remaining items were not touched")
    }

    @Test func unlockingNeverReachesThroughNestedSymlinks() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let lockedOutside = try fixture.write(fixture.outside.appendingPathComponent("locked.pdf"), bytes: 10)
        #expect(chflags(lockedOutside.path, UInt32(UF_IMMUTABLE)) == 0)
        let readOnlyOutside = fixture.outside.appendingPathComponent("ReadOnly")
        try FileManager.default.createDirectory(at: readOnlyOutside, withIntermediateDirectories: true)
        #expect(chmod(readOnlyOutside.path, 0o555) == 0)
        defer { chflags(lockedOutside.path, 0); chmod(readOnlyOutside.path, 0o755) }
        // A locked folder in the Trash (forcing the unlock pass) holding links to both.
        let folder = trash.appendingPathComponent("Folder")
        try fixture.write(folder.appendingPathComponent("locked-inside.txt"), bytes: 10)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link-to-locked"), withDestinationURL: lockedOutside)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link-to-readonly"), withDestinationURL: readOnlyOutside)
        #expect(chflags(folder.appendingPathComponent("locked-inside.txt").path, UInt32(UF_IMMUTABLE)) == 0)

        let result = try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash)

        #expect(result.failures.isEmpty)
        var info = stat()
        #expect(lstat(lockedOutside.path, &info) == 0 && info.st_flags & UInt32(UF_IMMUTABLE) != 0, "outside file still locked")
        #expect(lstat(readOnlyOutside.path, &info) == 0 && info.st_mode & 0o777 == 0o555, "outside folder still read-only")
    }

    @Test func windowsThumbnailCachesAreJunkOnlyWithTheirHeader() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        let real = volume.appendingPathComponent("Photos/Thumbs.db")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(JunkScanner.compoundFileMagic + [UInt8](repeating: 0, count: 504)).write(to: real)
        let decoy = try fixture.write(volume.appendingPathComponent("Docs/thumbs.db"), bytes: 100) // a user's SQLite file, say

        let report = try JunkScanner(policy: fixture.policy()).scan(volume: volume)
        #expect(report.items.map(\.category) == [.windowsThumbnails])
        #expect(JunkReport.defaultCategories.contains(.windowsThumbnails))

        _ = try JunkCleaner(policy: fixture.policy()).clean(report)
        #expect(!fixture.exists(real))
        #expect(fixture.exists(decoy))
    }

    @Test func volumeThatIsASymlinkToTheBootDiskIsRefused() throws {
        // /Volumes/Macintosh HD is a symlink to /. Validation only; nothing is deleted.
        let fixture = try Fixture()
        let bootAlias = fixture.volumes.appendingPathComponent("RTEST-BOOT")
        try FileManager.default.createSymbolicLink(at: bootAlias, withDestinationURL: URL(fileURLWithPath: "/"))
        #expect(throws: SafetyPolicy.Violation.self) { try fixture.policy().validateExternalVolume(bootAlias) }
        #expect(throws: SafetyPolicy.Violation.self) { try fixture.policy().validateTrashRoot(bootAlias.appendingPathComponent(".Trashes/\(fixture.uid)")) }
    }

    @Test func cleanerRejectsNonCanonicalPaths() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        try fixture.write(volume.appendingPathComponent("sub/x"), bytes: 1)
        let target = volume.appendingPathComponent("._foo")
        try Data(makeAppleDouble()).write(to: target)
        let sneaky = URL(fileURLWithPath: volume.path + "/sub/../._foo")
        let report = JunkReport(volume: volume, items: [JunkItem(url: sneaky, category: .appleDouble, bytes: 4096)])

        let result = try JunkCleaner(policy: fixture.policy()).clean(report)

        #expect(result.removedCount == 0)
        #expect(fixture.exists(target))
    }
}
