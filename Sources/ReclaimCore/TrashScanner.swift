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

/// Measures a trash folder: how many items, how much disk space, and which items are largest.
/// Sizes are allocated sizes (what deleting frees), and symlinks are never followed.
public struct TrashScanner: Sendable {
    /// Finder metadata that lives in every folder; counted in bytes but not shown as an item.
    static let hiddenItemNames: Set<String> = [".DS_Store"]

    public init() {}

    public func scan(root: URL, largestCount: Int = 20) -> TrashSummary {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .addedToDirectoryDateKey],
                options: []
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .empty
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .denied
        } catch {
            let code = (error as NSError).code
            return code == Int(EPERM) || code == Int(EACCES) ? .denied : .empty
        }

        var items: [TrashItem] = []
        var total: Int64 = 0
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .addedToDirectoryDateKey])
            let isSymlink = values?.isSymbolicLink ?? false
            let isDirectory = !isSymlink && (values?.isDirectory ?? false)
            let bytes = Self.allocatedSize(of: url, isDirectory: isDirectory, isSymlink: isSymlink)
            total += bytes
            guard !Self.hiddenItemNames.contains(url.lastPathComponent) else { continue }
            items.append(TrashItem(
                url: url,
                name: url.lastPathComponent,
                bytes: bytes,
                isDirectory: isDirectory,
                dateDeleted: values?.addedToDirectoryDate
            ))
        }

        let largest = items.sorted { ($0.bytes, $1.name) > ($1.bytes, $0.name) }.prefix(largestCount)
        return TrashSummary(access: .readable, itemCount: items.count, totalBytes: total, largestItems: Array(largest))
    }

    static func allocatedSize(of url: URL, isDirectory: Bool, isSymlink: Bool) -> Int64 {
        if isSymlink { return 0 }
        if !isDirectory { return fileAllocatedSize(url) }
        var total: Int64 = 0
        // The directory enumerator does not descend into symlinked directories.
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        for case let child as URL in enumerator {
            total += fileAllocatedSize(child)
        }
        return total
    }

    static func fileAllocatedSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]),
              values.isSymbolicLink != true
        else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
