import Foundation

public enum Paths {
    /// Whether anything (including a dangling symlink) exists at `path`.
    public static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The fully resolved path (symlinks, `..` and firmlinks such as /tmp → /private/tmp), or nil
    /// if the path doesn't exist. Uses realpath(3) because `URL.resolvingSymlinksInPath()`
    /// strips a leading /private, which would make containment checks unreliable.
    static func canonical(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// True when `path` is strictly inside `root` (not equal to it).
    static func isStrictlyInside(_ path: String, root: String) -> Bool {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) && path.count > prefix.count
    }

    static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    /// Lexically normalised absolute path with no `.`, `..` or repeated slashes left.
    ///
    /// Deliberately purely lexical: `URL.standardizedFileURL` and `NSString.standardizingPath`
    /// both rewrite `/private/tmp/...` to `/tmp/...`, which made every canonical-path comparison
    /// fail (see Build Journal, M2).
    static func normalized(_ url: URL) -> String {
        var components: [Substring] = []
        for component in url.path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": _ = components.popLast()
            default: components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }
}
