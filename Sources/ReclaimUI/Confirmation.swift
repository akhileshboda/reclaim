import Foundation
import ReclaimCore

/// A question the app asks before doing something it can't undo. The app target shows it as an
/// NSAlert; tests answer it directly.
public struct ConfirmationRequest: Sendable, Equatable {
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool

    public init(title: String, message: String, confirmTitle: String, isDestructive: Bool = true) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
    }

    // Wording follows Finder's own Empty Trash alert, plus the numbers Finder leaves out.

    public static func emptyTrash(driveName: String, itemCount: Int, bytes: Int64) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Are you sure you want to permanently erase the items in the Trash on “\(driveName)”?",
            message: "\(itemPhrase(itemCount)) (\(ByteFormat.string(bytes))) will be erased. You can’t undo this action.",
            confirmTitle: "Empty Trash"
        )
    }

    public static func emptyAllTrash(driveCount: Int, itemCount: Int, bytes: Int64) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Are you sure you want to permanently erase the items in the Trash on \(driveCount) drives?",
            message: "\(itemPhrase(itemCount)) (\(ByteFormat.string(bytes))) will be erased. You can’t undo this action.",
            confirmTitle: "Empty Trash"
        )
    }

    public static func deleteItems(names: [String], bytes: Int64) -> ConfirmationRequest {
        let subject = names.count == 1 ? "“\(names[0])”" : "\(names.count) items"
        return ConfirmationRequest(
            title: "Are you sure you want to permanently erase \(subject)?",
            message: "\(ByteFormat.string(bytes)) will be erased. You can’t undo this action.",
            confirmTitle: "Erase"
        )
    }

    public static func cleanJunk(driveName: String, fileCount: Int, bytes: Int64) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Remove hidden macOS files from “\(driveName)”?",
            message: "\(fileCount.formatted()) \(fileCount == 1 ? "file" : "files") (\(ByteFormat.string(bytes))) that macOS creates, such as .DS_Store and ._ files, will be removed. Your own files aren’t touched.",
            confirmTitle: "Remove"
        )
    }

    static func itemPhrase(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count.formatted()) items"
    }
}

@MainActor
public protocol Confirming: AnyObject {
    func confirm(_ request: ConfirmationRequest) async -> Bool
}

/// Answers every confirmation the same way and records what was asked.
@MainActor
public final class ScriptedConfirmer: Confirming {
    public var answer: Bool
    public private(set) var requests: [ConfirmationRequest] = []

    public init(answer: Bool) {
        self.answer = answer
    }

    public func confirm(_ request: ConfirmationRequest) async -> Bool {
        requests.append(request)
        return answer
    }
}
