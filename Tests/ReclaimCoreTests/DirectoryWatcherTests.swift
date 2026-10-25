import Foundation
import Testing
@testable import ReclaimCore

@MainActor @Suite struct DirectoryWatcherTests {
    @Test func reportsChangesInsideWatchedFolder() async throws {
        let fixture = try Fixture()
        let trash = try fixture.makeTrash(onVolume: "RTEST-UNIT")
        let (stream, continuation) = AsyncStream.makeStream(of: [String].self)
        let watcher = DirectoryWatcher(latency: 0.2) { paths in continuation.yield(paths) }
        watcher.watch([trash.path])
        try await Task.sleep(for: .milliseconds(300))

        try fixture.write(trash.appendingPathComponent("deleted.mov"), bytes: 1_000)

        let paths = await withTaskGroup(of: [String]?.self) { group in
            group.addTask { await stream.first { _ in true } }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        watcher.stop()
        let reported = try #require(paths, "FSEvents should report the change within 10 s")
        #expect(reported.contains { $0.hasPrefix(trash.path) })
    }
}
