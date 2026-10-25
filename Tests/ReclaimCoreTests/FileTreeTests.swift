import Foundation
import Testing
@testable import ReclaimCore

/// Regression suite for the M4 finding: FileManager silently hides files whose names start with
/// "._", so Reclaim lists files with POSIX APIs instead.
@Suite struct FileTreeTests {
    @Test func childrenIncludesAppleDoubleNames() throws {
        let fixture = try Fixture()
        try fixture.write(fixture.outside.appendingPathComponent("photo.jpg"), bytes: 10)
        try fixture.write(fixture.outside.appendingPathComponent("._photo.jpg"), bytes: 10)
        try fixture.write(fixture.outside.appendingPathComponent(".DS_Store"), bytes: 10)
        #expect(try FileTree.children(of: fixture.outside.path).sorted() == [".DS_Store", "._photo.jpg", "photo.jpg"])
    }

    @Test func walkSeesHiddenFilesAndNeverFollowsSymlinks() throws {
        let fixture = try Fixture()
        let tree = fixture.root.appendingPathComponent("tree")
        try fixture.write(tree.appendingPathComponent("a/._deep"), bytes: 10)
        try fixture.write(fixture.outside.appendingPathComponent("elsewhere.bin"), bytes: 10)
        try FileManager.default.createSymbolicLink(at: tree.appendingPathComponent("link"), withDestinationURL: fixture.outside)

        var seen: [String] = []
        FileTree.walk(tree.path) { entry in
            seen.append(entry.path.replacingOccurrences(of: tree.path, with: ""))
            return .continue
        }
        #expect(seen.sorted() == ["/a", "/a/._deep", "/link"])
    }

    @Test func allocatedSizeCountsHiddenFiles() throws {
        let fixture = try Fixture()
        let dir = fixture.root.appendingPathComponent("sized")
        try fixture.write(dir.appendingPathComponent("._big"), bytes: 1_000_000)
        #expect(FileTree.allocatedSize(of: dir.path) >= 1_000_000)
    }

    @Test func missingDirectoryThrows() {
        #expect(throws: POSIXError.self) { try FileTree.children(of: "/nonexistent-\(UUID().uuidString)") }
    }

    @Test func emptyingRemovesTopLevelAppleDoubleFiles() throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        try fixture.write(trash.appendingPathComponent("._Holiday.mp4"), bytes: 4_096)
        try fixture.write(trash.appendingPathComponent("Holiday.mp4"), bytes: 100_000)

        try fixture.write(trash.appendingPathComponent("._orphan"), bytes: 4_096)

        let summary = TrashScanner().scan(root: trash)
        #expect(summary.itemCount == 2, "companion ._Holiday.mp4 is hidden like Finder does; orphan ._orphan is listed")
        #expect(summary.totalBytes >= 108_192, "but every byte is counted")

        let result = try TrashEmptier(policy: fixture.policy()).emptyTrash(at: trash)
        #expect(result.removedCount == 3)
        #expect(try FileTree.children(of: trash.path).isEmpty)
    }
}
