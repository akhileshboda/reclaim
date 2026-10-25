import Foundation

/// The last line of defence before anything is deleted. Every destructive operation in
/// ReclaimCore asks the policy first, before touching the filesystem.
///
/// Rules:
/// - A trash root must be exactly `<home>/.Trash` (live mode only) or
///   `<volumes>/<Volume>/.Trashes/<uid>`, with no symlinks anywhere in its path.
/// - In sandbox mode only volumes named `RTEST-*` qualify, and the home Trash never does.
/// - A deletion target must sit strictly inside a validated root, and its parent directory must
///   resolve inside that root, so nothing is reached through a symlinked folder.
/// - A junk-cleanup volume must be a direct child of the volumes directory (never the boot volume).
public struct SafetyPolicy: Sendable {
    public enum Violation: Error, Equatable, CustomStringConvertible {
        case notATrashDirectory(String)
        case symlinkInPath(String)
        case outsideRoot(path: String, root: String)
        case notAllowedInSandbox(String)
        case notAVolume(String)

        public var description: String {
            switch self {
            case .notATrashDirectory(let path): "Refusing: \(path) is not a recognised Trash folder."
            case .symlinkInPath(let path): "Refusing: \(path) is reached through a symbolic link."
            case .outsideRoot(let path, let root): "Refusing: \(path) is outside \(root)."
            case .notAllowedInSandbox(let path): "Refusing: \(path) is not a sandbox test volume."
            case .notAVolume(let path): "Refusing: \(path) is not an external volume."
            }
        }
    }

    public let mode: RuntimeMode
    public let homeDirectory: URL
    public let volumesDirectory: URL
    public let userID: uid_t

    public init(
        mode: RuntimeMode,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        volumesDirectory: URL = URL(fileURLWithPath: "/Volumes", isDirectory: true),
        userID: uid_t = getuid()
    ) {
        self.mode = mode
        self.homeDirectory = homeDirectory
        self.volumesDirectory = volumesDirectory
        self.userID = userID
    }

    /// Validates a trash folder and returns its canonical path.
    @discardableResult
    public func validateTrashRoot(_ root: URL) throws -> String {
        let path = Paths.normalized(root)
        guard let canonical = Paths.canonical(path) else { throw Violation.notATrashDirectory(path) }
        // Any symlink in the chain (e.g. .Trashes pointing at someone's home) changes the path.
        guard canonical == path else { throw Violation.symlinkInPath(path) }

        let homeTrash = Paths.normalized(homeDirectory.appendingPathComponent(".Trash"))
        if path == homeTrash {
            guard mode == .live else { throw Violation.notAllowedInSandbox(path) }
            return canonical
        }

        let volumes = Paths.normalized(volumesDirectory)
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let volumeComponents = volumes.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Expect exactly: <volumes>/<Volume>/.Trashes/<uid>
        guard components.count == volumeComponents.count + 3,
              Array(components.prefix(volumeComponents.count)) == volumeComponents,
              components[volumeComponents.count + 1] == ".Trashes",
              components[volumeComponents.count + 2] == String(userID)
        else { throw Violation.notATrashDirectory(path) }

        let volumeName = components[volumeComponents.count]
        if mode == .sandbox, !volumeName.hasPrefix(RuntimeMode.sandboxVolumePrefix) {
            throw Violation.notAllowedInSandbox(path)
        }
        return canonical
    }

    /// Validates a volume for junk cleanup and returns its canonical path.
    @discardableResult
    public func validateJunkVolume(_ volume: URL) throws -> String {
        let path = Paths.normalized(volume)
        guard let canonical = Paths.canonical(path), canonical == path else { throw Violation.symlinkInPath(path) }
        let volumes = Paths.normalized(volumesDirectory)
        guard Paths.isStrictlyInside(path, root: volumes),
              !path.dropFirst(volumes.count + 1).contains("/")
        else { throw Violation.notAVolume(path) }
        if mode == .sandbox, !volume.lastPathComponent.hasPrefix(RuntimeMode.sandboxVolumePrefix) {
            throw Violation.notAllowedInSandbox(path)
        }
        return canonical
    }

    /// Validates one deletion target against an already-validated canonical root.
    /// The target itself may be a symlink (it gets unlinked, never followed).
    public func validateTarget(_ target: URL, withinCanonicalRoot root: String) throws {
        let path = Paths.normalized(target)
        guard Paths.isStrictlyInside(path, root: root) else { throw Violation.outsideRoot(path: path, root: root) }
        let parent = (path as NSString).deletingLastPathComponent
        guard let canonicalParent = Paths.canonical(parent),
              canonicalParent == root || Paths.isStrictlyInside(canonicalParent, root: root)
        else { throw Violation.symlinkInPath(path) }
        guard canonicalParent == parent else { throw Violation.symlinkInPath(path) }
    }
}
