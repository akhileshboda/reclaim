import Foundation
import Testing
@testable import ReclaimCore
@testable import ReclaimUI

/// The notice is what the person reads after Empty Trash. It must say why items were left, not
/// report "Reclaimed Zero KB" with a guess.
@MainActor
@Suite struct NoticeTests {
    private func failure(_ name: String, _ reason: String) -> RemovalResult.Failure {
        .init(url: URL(fileURLWithPath: "/Volumes/Test/.Trashes/501/\(name)"), reason: reason)
    }

    @Test func nothingErasedNamesTheReason() {
        var result = RemovalResult()
        result.failures = [failure("Locked.pdf", "The operation couldn’t be completed. Operation not permitted")]
        let notice = AppModel.notice(for: [("Macintosh HD", .success(result))], scope: "on “Macintosh HD”")

        #expect(notice.kind == .warning)
        #expect(notice.text.contains("1 item couldn’t be erased."))
        #expect(notice.text.contains("Operation not permitted"))
        #expect(!notice.text.contains("Reclaimed"))
        #expect(!notice.text.contains("may be in use"))
    }

    @Test func partialSuccessKeepsTheCountAndTheReason() {
        var result = RemovalResult()
        result.removedCount = 2
        result.freedBytes = 1_000
        result.failures = [
            failure("A", "Permission denied"),
            failure("B", "Permission denied"),
        ]
        let notice = AppModel.notice(for: [("Macintosh HD", .success(result))], scope: "on “Macintosh HD”")

        #expect(notice.kind == .warning)
        #expect(notice.text.hasPrefix("Reclaimed "))
        #expect(notice.text.contains("2 items couldn’t be erased. First problem: Permission denied."))
    }

    @Test func fullSuccessStaysSuccess() {
        var result = RemovalResult()
        result.removedCount = 3
        result.freedBytes = 3_000
        let notice = AppModel.notice(for: [("Macintosh HD", .success(result))], scope: "on “Macintosh HD”")

        #expect(notice.kind == .success)
        #expect(notice.text.hasPrefix("Reclaimed "))
    }
}
