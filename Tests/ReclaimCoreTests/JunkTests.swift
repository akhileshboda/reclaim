import Foundation
import Testing
@testable import ReclaimCore

@Suite struct JunkTests {
    func writeAppleDouble(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(JunkScanner.appleDoubleMagic + [UInt8](repeating: 0, count: 4092)).write(to: url)
    }

    func writeDSStore(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(JunkScanner.dsStoreMagic + [UInt8](repeating: 0, count: 6136)).write(to: url)
    }

    func makeJunkVolume(_ fixture: Fixture, name: String = "RTEST-USB") throws -> URL {
        let volume = try fixture.makeVolume(name)
        try writeDSStore(volume.appendingPathComponent(".DS_Store"))
        try writeDSStore(volume.appendingPathComponent("Photos/.DS_Store"))
        try fixture.write(volume.appendingPathComponent("Photos/photo.jpg"), bytes: 100_000)
        try writeAppleDouble(volume.appendingPathComponent("Photos/._photo.jpg"))
        try FileManager.default.createDirectory(at: volume.appendingPathComponent(".TemporaryItems"), withIntermediateDirectories: true)
        try fixture.write(volume.appendingPathComponent(".TemporaryItems/folders.501"), bytes: 10)
        try fixture.write(volume.appendingPathComponent(".Spotlight-V100/Store-V2/index"), bytes: 50_000)
        try fixture.write(volume.appendingPathComponent(".fseventsd/0000001"), bytes: 1_000)
        try fixture.write(volume.appendingPathComponent(".Trashes/\(fixture.uid)/._deleted"), bytes: 10)
        return volume
    }

    @Test func findsEachCategoryByContent() throws {
        let fixture = try Fixture()
        let volume = try makeJunkVolume(fixture)
        let report = try JunkScanner(policy: fixture.policy()).scan(volume: volume)
        #expect(report.count(of: .finderMetadata) == 2)
        #expect(report.count(of: .appleDouble) == 1)
        #expect(report.count(of: .temporary) == 1)
        #expect(report.count(of: .systemIndexes) == 2)
        #expect(!report.items.contains { $0.url.path.contains("/.Trashes/") }, "trash is handled separately")
        #expect(!report.items.contains { $0.url.lastPathComponent == "photo.jpg" })
    }

    @Test func junkNamedUserFilesAreNotJunk() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-USB")
        try fixture.write(volume.appendingPathComponent("._notes.txt"), bytes: 200)      // no AppleDouble magic
        try fixture.write(volume.appendingPathComponent("Docs/.DS_Store"), bytes: 200)   // no Bud1 magic
        try fixture.write(volume.appendingPathComponent("._"), bytes: 10)
        let report = try JunkScanner(policy: fixture.policy()).scan(volume: volume)
        #expect(report.items.isEmpty)
    }

    @Test func cleaningRemovesOnlyJunkAndKeepsUserFiles() throws {
        let fixture = try Fixture()
        let volume = try makeJunkVolume(fixture)
        let decoy = try fixture.write(volume.appendingPathComponent("Photos/._notes-from-user.txt"), bytes: 300)
        let policy = fixture.policy()
        let report = try JunkScanner(policy: policy).scan(volume: volume).filtered(to: [.finderMetadata, .appleDouble, .temporary])

        let result = try JunkCleaner(policy: policy).clean(report)

        #expect(result.failures.isEmpty)
        #expect(result.removedCount == 4)
        #expect(fixture.exists(decoy))
        #expect(fixture.exists(volume.appendingPathComponent("Photos/photo.jpg")))
        #expect(fixture.exists(volume.appendingPathComponent(".Spotlight-V100")), "system indexes stay unless asked")
        #expect(try JunkScanner(policy: policy).scan(volume: volume).filtered(to: [.finderMetadata, .appleDouble, .temporary]).items.isEmpty)
    }

    @Test func fileSwappedAfterScanIsLeftAlone() throws {
        let fixture = try Fixture()
        let volume = try makeJunkVolume(fixture)
        let policy = fixture.policy()
        let report = try JunkScanner(policy: policy).scan(volume: volume).filtered(to: [.appleDouble])
        // Between scan and clean, the user's own file appears at the same path.
        try Data("user content".utf8).write(to: volume.appendingPathComponent("Photos/._photo.jpg"))

        let result = try JunkCleaner(policy: policy).clean(report)

        #expect(result.removedCount == 0)
        #expect(fixture.exists(volume.appendingPathComponent("Photos/._photo.jpg")))
    }

    @Test func refusesBootHomeAndRealVolumesInSandbox() throws {
        let fixture = try Fixture()
        let scanner = JunkScanner(policy: fixture.policy())
        #expect(throws: SafetyPolicy.Violation.self) { try scanner.scan(volume: fixture.home) }
        #expect(throws: SafetyPolicy.Violation.self) { try scanner.scan(volume: try fixture.makeVolume("Camera")) }
        #expect(throws: SafetyPolicy.Violation.self) { try JunkScanner(policy: SafetyPolicy(mode: .live)).scan(volume: URL(fileURLWithPath: "/")) }
    }

    @Test func refusesTimeMachineVolumes() throws {
        let fixture = try Fixture()
        let volume = try fixture.makeVolume("RTEST-TM")
        try FileManager.default.createDirectory(at: volume.appendingPathComponent("Backups.backupdb"), withIntermediateDirectories: true)
        #expect(throws: JunkScanner.ScanError.timeMachineVolume) { try JunkScanner(policy: fixture.policy()).scan(volume: volume) }
    }

    @Test func cleanerRejectsItemsOutsideTheVolume() throws {
        let fixture = try Fixture()
        let volume = try makeJunkVolume(fixture)
        let outside = fixture.outside.appendingPathComponent("._x")
        try writeAppleDouble(outside)
        let forged = JunkReport(volume: volume, items: [JunkItem(url: outside, category: .appleDouble, bytes: 4096)])

        let result = try JunkCleaner(policy: fixture.policy()).clean(forged)

        #expect(result.removedCount == 0)
        #expect(result.failures.count == 1)
        #expect(fixture.exists(outside))
    }
}
