import Foundation
import ReclaimCore

/// A question the app asks before doing something it can't undo. The app target shows it as an
/// NSAlert; tests answer it directly.
public struct ConfirmationRequest: Sendable, Equatable {
    public let title: String
    public let message: String
    public let confirmTitle: String
    public let isDestructive: Bool

    public init(title: String, message: String, confirmTitle: String, isDestructive: Bool = false) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
    }

    // Short, specific titles; the message carries the numbers and the consequence. The confirm
    // button is not styled destructive: per the HIG, when people deliberately choose Empty
    // Trash, the button carries out their intent rather than an unexpected side effect.

    public static func emptyTrash(driveName: String, itemCount: Int, bytes: Int64) -> ConfirmationRequest {
        ConfirmationRequest(
            title: "Empty the Trash on “\(driveName)”?",
            message: "\(itemPhrase(itemCount)) (\(ByteFormat.string(bytes))) will be permanently erased. You can’t undo this action.",
            confirmTitle: "Empty Trash"
        )
    }

    public static func emptyAllTrash(driveNames: [String], itemCount: Int, bytes: Int64) -> ConfirmationRequest {
        let names = ListFormatter.localizedString(byJoining: driveNames.map { "“\($0)”" })
        return ConfirmationRequest(
            title: "Empty the Trash on \(driveNames.count) drives?",
            message: "\(itemPhrase(itemCount)) (\(ByteFormat.string(bytes))) on \(names) will be permanently erased. You can’t undo this action.",
            confirmTitle: "Empty Trash"
        )
    }

    public static func deleteItems(names: [String], bytes: Int64) -> ConfirmationRequest {
        let subject = names.count == 1 ? "“\(names[0])”" : "\(names.count) items"
        return ConfirmationRequest(
            title: "Erase \(subject) immediately?",
            message: "\(ByteFormat.string(bytes)) will be permanently erased. You can’t undo this action.",
            confirmTitle: "Erase"
        )
    }

    public static func cleanJunk(driveName: String, fileCount: Int, bytes: Int64, keptWithMetadata: Int = 0) -> ConfirmationRequest {
        var message = "\(fileCount.formatted()) \(fileCount == 1 ? "file" : "files") (\(ByteFormat.string(bytes))) that macOS creates, such as .DS_Store and ._ files, will be removed."
        if keptWithMetadata > 0 {
            message += " \(keptWithMetadata.formatted()) ._ \(keptWithMetadata == 1 ? "file holds" : "files hold") Finder tags or other metadata and will be kept."
        }
        return ConfirmationRequest(
            title: "Remove hidden macOS files from “\(driveName)”?",
            message: message,
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
    /// Runs while the "alert" is up, to simulate things changing behind it (NSAlert's modal loop
    /// keeps processing mount notifications and refreshes).
    public var whileAsking: (() async -> Void)?

    public init(answer: Bool) {
        self.answer = answer
    }

    public func confirm(_ request: ConfirmationRequest) async -> Bool {
        requests.append(request)
        await whileAsking?()
        return answer
    }
}
