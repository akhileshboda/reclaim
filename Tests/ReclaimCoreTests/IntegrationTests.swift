import Foundation
import Testing
@testable import ReclaimCore

/// Runs against the real throwaway RTEST-* disks created by `Scripts/sandbox.sh`.
/// Enabled only by `make test-integration`, which re-seeds the disks and runs inside the
/// kernel sandbox (RECLAIM_SANDBOXED=1). Anything else skips these tests.
enum IntegrationGate {
    static var enabled: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["RECLAIM_INTEGRATION"] == "1" && env["RECLAIM_SANDBOXED"] == "1"
    }
}

@Suite(.enabled(if: IntegrationGate.enabled), .serialized)
struct CoreIntegrationTests {
    let provider = VolumeProvider(mode: .sandbox)
    let locator = TrashLocator(mode: .sandbox)

    @Test func discoversOnlyTheSandboxDisks() {
        let drives = provider.mountedDrives()
        #expect(drives.map(\.name) == ["RTEST-CAM", "RTEST-HFS", "RTEST-SSD", "RTEST-USB"])
        for drive in drives {
            #expect(!drive.isBoot)
            #expect(drive.totalBytes > 0)
            #expect(drive.freeBytes > 0)
        }
        #expect(drives.first { $0.name == "RTEST-SSD" }?.fileSystem?.lowercased() == "apfs")
    }

    @Test func scansSeededTrash() throws {
        let ssd = try #require(provider.mountedDrives().first { $0.name == "RTEST-SSD" })
        let trash = try #require(locator.trashURL(for: ssd))
        let summary = TrashScanner().scan(root: trash)
        #expect(summary.access == .readable)
        #expect(summary.largestItems.first?.name == "Interview_A-cam.mov")
        #expect(summary.totalBytes > 300_000_000)
    }

    @Test func emptyingHFSDiskFreesSpaceAndKeepsUserData() throws {
        let hfs = try #require(provider.mountedDrives().first { $0.name == "RTEST-HFS" })
        let trash = try #require(locator.trashURL(for: hfs))
        let before = TrashScanner().scan(root: trash)
        #expect(before.totalBytes >= 50_000_000)

        let result = try TrashEmptier(policy: SafetyPolicy(mode: .sandbox)).emptyTrash(at: trash)

        #expect(result.failures.isEmpty)
        #expect(result.freedBytes >= 50_000_000)
        #expect(TrashScanner().scan(root: trash).totalBytes == 0)
        let after = try #require(provider.mountedDrives().first { $0.name == "RTEST-HFS" })
        #expect(after.freeBytes - hfs.freeBytes >= 45_000_000, "free space should grow by roughly the trash size")
        #expect(FileManager.default.fileExists(atPath: hfs.url.appendingPathComponent("Keep/important.txt").path))
    }
}
