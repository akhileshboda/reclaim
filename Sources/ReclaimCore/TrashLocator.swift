import Foundation

/// Finds where macOS puts deleted files for a given drive.
///
/// Files deleted from the boot drive go to `~/.Trash`. Files deleted from any other volume go to
/// that volume's `.Trashes/<uid>` folder, which is why emptying "the Trash" is per drive.
public struct TrashLocator: Sendable {
    public let mode: RuntimeMode
    public let homeDirectory: URL
    public let userID: uid_t

    public init(
        mode: RuntimeMode,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        userID: uid_t = getuid()
    ) {
        self.mode = mode
        self.homeDirectory = homeDirectory
        self.userID = userID
    }

    /// The trash folder for `drive`, or nil when sandbox mode hides it (the boot drive).
    public func trashURL(for drive: DriveInfo) -> URL? {
        if drive.isBoot {
            return mode == .live ? homeDirectory.appendingPathComponent(".Trash", isDirectory: true) : nil
        }
        return drive.url
            .appendingPathComponent(".Trashes", isDirectory: true)
            .appendingPathComponent(String(userID), isDirectory: true)
    }
}
