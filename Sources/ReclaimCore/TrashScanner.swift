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
        let nameSet = Set(names)
        for name in names {
            let url = root.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { continue }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            let bytes = FileTree.allocatedSize(of: url.path)
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

        let largest = items.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }.prefix(largestCount)
        return TrashSummary(access: .readable, itemCount: items.count, totalBytes: total, largestItems: Array(largest))
    }
}
