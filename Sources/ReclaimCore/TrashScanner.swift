import Foundation

public struct TrashItem: Sendable, Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bytes: Int64
    public let isDirectory: Bool
    /// When the item was moved to the Trash, if the file system records it.
    public let dateDeleted: Date?

    public init(url: URL, name: String, bytes: Int64, isDirectory: Bool, dateDeleted: Date?) {
        self.url = url
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.dateDeleted = dateDeleted
    }
}

public struct TrashSummary: Sendable, Equatable {
    public enum Access: Sendable, Equatable {
        case readable
        /// The folder exists but macOS refused to list it (Full Disk Access for ~/.Trash).
        case denied
        /// No trash folder (nothing has been deleted on this drive yet) or sandbox mode hides it.
        case unavailable
    }

    public let access: Access
    public let itemCount: Int
    public let totalBytes: Int64
    public let largestItems: [TrashItem]

    public static let empty = TrashSummary(access: .unavailable, itemCount: 0, totalBytes: 0, largestItems: [])
    public static let denied = TrashSummary(access: .denied, itemCount: 0, totalBytes: 0, largestItems: [])

    public init(access: Access, itemCount: Int, totalBytes: Int64, largestItems: [TrashItem]) {
        self.access = access
        self.itemCount = itemCount
        self.totalBytes = totalBytes
        self.largestItems = largestItems
    }
}

public protocol TrashScanning: Sendable {
    func scan(root: URL, largestCount: Int) -> TrashSummary
}

/// Measures a trash folder: how many items, how much disk space, and which items are largest.
/// Sizes are allocated sizes (what deleting frees), and symlinks are never followed.
public struct TrashScanner: TrashScanning {
    /// Finder metadata that lives in every folder; counted in bytes but not shown as an item.
    static let hiddenItemNames: Set<String> = [".DS_Store"]

    static func isAppleDoubleCompanion(_ name: String, in names: Set<String>) -> Bool {
        name.hasPrefix("._") && names.contains(String(name.dropFirst(2)))
    }

    /// Sizes of items measured by earlier scans. Every change to a Trash folder triggers a
    /// rescan, and re-measuring a big folder that's been sitting there is minutes of disk work.
    private let sizes = SizeCache()

    public init() {}

    public func scan(root: URL, largestCount: Int = 20) -> TrashSummary {
        let names: [String]
        do {
            names = try FileTree.children(of: root.path)
        } catch let error as POSIXError where error.code == .EPERM || error.code == .EACCES {
            return .denied
        } catch {
            return .empty
        }

        var items: [TrashItem] = []
        var total: Int64 = 0
        var seen: Set<String> = []
        let nameSet = Set(names)
        for name in names {
            let url = root.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            let key = SizeCache.Key(info)
            let bytes: Int64
            if let cached = sizes.size(at: url.path, key: key) {
                bytes = cached
            } else {
                bytes = FileTree.allocatedSize(of: url.path)
                sizes.store(bytes, at: url.path, key: key)
            }
            seen.insert(url.path)
            total += bytes
            // Finder metadata, and "._X" AppleDouble companions of an item "X" on non-Mac formats,
            // are counted in bytes and deleted with everything else, but not listed, as in Finder.
            guard !Self.hiddenItemNames.contains(name), !Self.isAppleDoubleCompanion(name, in: nameSet) else { continue }
            items.append(TrashItem(
                url: url,
                name: name,
                bytes: bytes,
                isDirectory: isDirectory,
                dateDeleted: (try? url.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
            ))
        }

        sizes.forget(under: root.path, except: seen)
        let largest = items.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }.prefix(largestCount)
        return TrashSummary(access: .readable, itemCount: items.count, totalBytes: total, largestItems: Array(largest))
    }
}

/// Remembers what each Trash item measured, keyed by its identity and change times. A file's
/// size or a folder's direct contents changing updates its modification or status-change time,
/// so the entry stops matching and the item is measured again.
final class SizeCache: @unchecked Sendable {
    struct Key: Equatable {
        let device: Int64
        let inode: UInt64
        let modified: timespec
        let changed: timespec

        init(_ info: stat) {
            device = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
            modified = info.st_mtimespec
            changed = info.st_ctimespec
        }

        static func == (a: Key, b: Key) -> Bool {
            a.device == b.device && a.inode == b.inode
                && a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec
                && a.changed.tv_sec == b.changed.tv_sec && a.changed.tv_nsec == b.changed.tv_nsec
        }
    }

    private let lock = NSLock()
    private var entries: [String: (key: Key, bytes: Int64)] = [:]

    func size(at path: String, key: Key) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path], entry.key == key else { return nil }
        return entry.bytes
    }

    func store(_ bytes: Int64, at path: String, key: Key) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = (key, bytes)
    }

    /// Drops entries for items that have left the Trash at `root`.
    func forget(under root: String, except seen: Set<String>) {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { !$0.key.hasPrefix(prefix) || seen.contains($0.key) }
    }
}
