import Testing
import Foundation
@testable import ReclaimCore

@Suite("Full Disk Access probe")
struct FullDiskAccessTests {
    private func probe(_ results: [String: Int32], paths: [String] = ["a", "b", "c"]) -> FullDiskAccessProbe {
        FullDiskAccessProbe(paths: paths, open: { results[$0] ?? ENOENT })
    }

    @Test func readableFolderMeansGranted() {
        #expect(probe(["a": 0]).status() == .granted)
    }

    @Test func eitherPermissionErrorMeansDenied() {
        #expect(probe(["a": EPERM]).status() == .denied)
        #expect(probe(["a": EACCES]).status() == .denied)
    }

    @Test func missingFoldersAreSkippedUntilOneAnswers() {
        #expect(probe(["c": EPERM]).status() == .denied)
        #expect(probe(["b": 0]).status() == .granted)
    }

    @Test func nothingToCheckIsUnknown() {
        #expect(probe([:]).status() == .unknown)
        #expect(probe(["a": EIO]).status() == .unknown)
    }

    @Test func aDenialStopsTheProbeSoOnlyOneFolderIsTouched() {
        let touched = LockedBox<[String]>([])
        let probe = FullDiskAccessProbe(paths: ["a", "b"], open: { path in
            touched.mutate { $0.append(path) }
            return EPERM
        })
        _ = probe.status()
        #expect(touched.value == ["a"])
    }
}

private final class LockedBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ change: (inout T) -> Void) { lock.withLock { change(&stored) } }
}
