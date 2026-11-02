import Foundation

/// Whether macOS lets Reclaim read folders that need Full Disk Access.
public enum FullDiskAccessStatus: Sendable, Equatable {
    case granted
    case denied
    /// None of the probe folders could be checked (all missing), so nothing is known either way.
    case unknown
}

/// Asks macOS whether Full Disk Access is on by opening a folder that only it unlocks.
///
/// A denied open also makes macOS add the app to Privacy & Security › Full Disk Access with its
/// switch off, which is what lets the person turn Reclaim on instead of adding it with +.
public struct FullDiskAccessProbe: Sendable {
    /// Returns 0 when `path` could be opened, otherwise the errno.
    public typealias Open = @Sendable (String) -> Int32

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    private let paths: [String]
    private let open: Open

    /// Folders that need Full Disk Access on every Mac, tried in order until one exists.
    public static func defaultPaths(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        ["Library/Safari", "Library/Mail", "Library/Messages", ".Trash"].map { home.appendingPathComponent($0).path }
    }

    public init(paths: [String] = Self.defaultPaths(), open: @escaping Open = Self.openDirectory) {
        self.paths = paths
        self.open = open
    }

    public func status() -> FullDiskAccessStatus {
        for path in paths {
            switch open(path) {
            case 0: return .granted
            case EPERM, EACCES: return .denied
            default: continue
            }
        }
        return .unknown
    }

    public static let openDirectory: Open = { path in
        guard let dir = opendir(path) else { return errno }
        closedir(dir)
        return 0
    }
}
