import Foundation

public struct RemovalResult: Sendable, Equatable {
    public struct Failure: Sendable, Equatable {
        public let url: URL
        public let reason: String
    }

    public var removedCount = 0
    public var freedBytes: Int64 = 0
    public var failures: [Failure] = []

    public init() {}

    mutating func merge(_ other: RemovalResult) {
        removedCount += other.removedCount
        freedBytes += other.freedBytes
        failures += other.failures
    }
}

/// Deletes items under a validated root, clearing the locks and permission bits Finder would
/// clear, and never following symlinks.
public protocol FileRemoving: Sendable {
    func removeItem(atPath path: String) throws
}

public struct SystemFileRemover: FileRemoving {
    public init() {}
    public func removeItem(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}

public struct TrashEmptier: Sendable {
    public let policy: SafetyPolicy
    let remover: any FileRemoving

    public init(policy: SafetyPolicy, remover: any FileRemoving = SystemFileRemover()) {
        self.policy = policy
        self.remover = remover
    }

    /// Permanently deletes everything in the trash folder at `root`.
    public func emptyTrash(at root: URL) throws -> RemovalResult {
        let canonicalRoot = try policy.validateTrashRoot(root)
        let children = (try? FileManager.default.contentsOfDirectory(atPath: canonicalRoot)) ?? []
        let targets = children.map { URL(fileURLWithPath: canonicalRoot).appendingPathComponent($0) }
        return remove(targets, canonicalRoot: canonicalRoot)
    }

    /// Permanently deletes specific items from the trash folder at `root` (Trash peek).
    /// Every item is validated before anything is deleted, so one bad path deletes nothing.
    public func removeItems(_ items: [URL], fromTrashAt root: URL) throws -> RemovalResult {
        let canonicalRoot = try policy.validateTrashRoot(root)
        for item in items { try policy.validateTarget(item, withinCanonicalRoot: canonicalRoot) }
        return remove(items, canonicalRoot: canonicalRoot)
    }

    func remove(_ targets: [URL], canonicalRoot: String) -> RemovalResult {
        var result = RemovalResult()
        for target in targets {
            result.merge(removeOne(target, canonicalRoot: canonicalRoot))
        }
        return result
    }

    func removeOne(_ target: URL, canonicalRoot: String) -> RemovalResult {
        var result = RemovalResult()
        let path = Paths.normalized(target)
        do {
            try policy.validateTarget(target, withinCanonicalRoot: canonicalRoot)
        } catch {
            result.failures.append(.init(url: target, reason: String(describing: error)))
            return result
        }

        let bytes = Self.measure(path)
        do {
            try remover.removeItem(atPath: path)
        } catch {
            // Locked files (uchg) and read-only folders: clear the flags inside the target, then retry.
            Self.unlockTree(at: path, canonicalRoot: canonicalRoot)
            do {
                try remover.removeItem(atPath: path)
            } catch {
                result.failures.append(.init(url: target, reason: error.localizedDescription))
                return result
            }
        }
        result.removedCount = 1
        result.freedBytes = bytes
        return result
    }

    static func measure(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let isSymlink = Paths.isSymlink(path)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        guard exists || isSymlink else { return 0 }
        return TrashScanner.allocatedSize(of: url, isDirectory: isDirectory.boolValue && !isSymlink, isSymlink: isSymlink)
    }

    /// Clears user immutable/append-only flags and restores owner write permission on every
    /// non-symlink entry under `path`. Each entry is re-checked to be inside the root first.
    static func unlockTree(at path: String, canonicalRoot: String) {
        unlock(path, canonicalRoot: canonicalRoot)
        guard !Paths.isSymlink(path),
              let enumerator = FileManager.default.enumerator(atPath: path) else { return }
        for case let relative as String in enumerator {
            unlock((path as NSString).appendingPathComponent(relative), canonicalRoot: canonicalRoot)
        }
    }

    private static func unlock(_ path: String, canonicalRoot: String) {
        guard Paths.isStrictlyInside(path, root: canonicalRoot) else { return }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return }
        let lockFlags = UInt32(UF_IMMUTABLE | UF_APPEND)
        if info.st_flags & lockFlags != 0 {
            _ = lchflags(path, info.st_flags & ~lockFlags)
        }
        if (info.st_mode & S_IFMT) == S_IFDIR, info.st_mode & S_IWUSR == 0 {
            _ = chmod(path, (info.st_mode & 0o7777) | S_IRWXU)
        }
    }
}
