import Foundation

/// Directory listing and walking with POSIX APIs.
///
/// Foundation's `FileManager` (contentsOfDirectory and both enumerators) silently omits files
/// whose names start with `._`, which are exactly the AppleDouble files Reclaim cleans, and
/// which also live in Trash folders. Everything that lists files goes through here instead.
public enum FileTree {
    public struct Entry {
        public let path: String
        public let name: String
        /// Depth below the walk's root (the root's children are level 1).
        public let level: Int
        public let isDirectory: Bool
        public let isSymlink: Bool
        public let isRegularFile: Bool
        public let allocatedBytes: Int64
        /// Number of hard links; above 1, the same blocks are reachable by another name.
        public let linkCount: Int
        let inode: ino_t
    }

    public enum Decision { case `continue`, skipDescendants }

    /// Names of the entries directly inside `path` (no "." or ".."), including `._` files.
    public static func children(of path: String) throws -> [String] {
        guard let dir = opendir(path) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { closedir(dir) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(dir) else {
                // NULL means the end, or an error part-way through; never return a partial list.
                if errno != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                return names
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
    }

    /// Visits everything below `path` (not `path` itself) in pre-order. Never follows symlinks
    /// and never crosses into another mounted file system. `onError` receives each folder that
    /// couldn't be read (path and errno), including the root.
    public static func walk(_ path: String, onError: ((String, Int32) -> Void)? = nil, _ visit: (Entry) -> Decision) {
        let options = FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR
        path.withCString { cPath in
            var argv: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: cPath), nil]
            guard let fts = fts_open(&argv, options, nil) else {
                onError?(path, errno)
                return
            }
            defer { fts_close(fts) }
            while let node = fts_read(fts) {
                let info = Int32(node.pointee.fts_info)
                if info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                    onError?(String(cString: node.pointee.fts_path), node.pointee.fts_errno)
                    continue
                }
                if info == FTS_DP || node.pointee.fts_level == 0 { continue } // post-order visit / the root
                let entryPath = String(cString: node.pointee.fts_path)
                let stat = node.pointee.fts_statp?.pointee
                let mode = stat.map { $0.st_mode & S_IFMT } ?? 0
                let entry = Entry(
                    path: entryPath,
                    name: (entryPath as NSString).lastPathComponent,
                    level: Int(node.pointee.fts_level),
                    isDirectory: mode == S_IFDIR,
                    isSymlink: mode == S_IFLNK,
                    isRegularFile: mode == S_IFREG,
                    allocatedBytes: mode == S_IFREG ? Int64(stat?.st_blocks ?? 0) * 512 : 0,
                    linkCount: Int(stat?.st_nlink ?? 1),
                    inode: stat?.st_ino ?? 0
                )
                if visit(entry) == .skipDescendants, entry.isDirectory {
                    fts_set(fts, node, FTS_SKIP)
                }
            }
        }
    }

    /// Allocated bytes of a file, or of every regular file under a directory. Symlinks count as 0,
    /// and a hard-linked file is counted once however many of its names are inside.
    public static func allocatedSize(of path: String) -> Int64 {
        var info = stat()
        guard lstat(path, &info) == 0 else { return 0 }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            return Int64(info.st_blocks) * 512
        case S_IFDIR:
            var total: Int64 = 0
            var seenLinkedInodes: Set<ino_t> = []
            walk(path) { entry in
                if entry.linkCount > 1, !seenLinkedInodes.insert(entry.inode).inserted { return .continue }
                total += entry.allocatedBytes
                return .continue
            }
            return total
        default:
            return 0
        }
    }
}
