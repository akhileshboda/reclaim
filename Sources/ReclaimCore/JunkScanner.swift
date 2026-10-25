import Foundation

/// Hidden files macOS leaves on drives, which clutter TVs, cameras, car stereos and Windows PCs.
public enum JunkCategory: String, CaseIterable, Sendable, Identifiable {
    /// `.DS_Store`: Finder view settings.
    case finderMetadata
    /// `._name`: AppleDouble sidecars that are orphaned or hold only disposable system metadata.
    case appleDouble
    /// `._name` sidecars that hold Finder tags, comments, a colour label, a resource fork or an
    /// unknown attribute. Reported, but never removed by default: deleting them loses metadata.
    case appleDoubleWithMetadata
    /// `.TemporaryItems`, `.apdisk`.
    case temporary
    /// `.Spotlight-V100`, `.fseventsd`: rebuilt automatically, so only removed when asked to.
    case systemIndexes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .finderMetadata: "Finder folder settings (.DS_Store)"
        case .appleDouble: "AppleDouble files (._)"
        case .appleDoubleWithMetadata: "AppleDouble files holding Finder tags or other metadata"
        case .temporary: "Temporary items"
        case .systemIndexes: "Spotlight index and FSEvents logs"
        }
    }
}

public struct JunkItem: Sendable, Hashable {
    public let url: URL
    public let category: JunkCategory
    public let bytes: Int64
}

public struct JunkReport: Sendable, Equatable {
    public let volume: URL
    public let items: [JunkItem]
    /// Folders the scan couldn't read and skipped.
    public var unreadableFolders = 0

    public init(volume: URL, items: [JunkItem], unreadableFolders: Int = 0) {
        self.volume = volume
        self.items = items
        self.unreadableFolders = unreadableFolders
    }

    /// What "Remove Hidden macOS Files" removes unless the user opts into more.
    public static let defaultCategories: Set<JunkCategory> = [.finderMetadata, .appleDouble, .temporary]

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    public func count(of category: JunkCategory) -> Int { items.filter { $0.category == category }.count }

    public func filtered(to categories: Set<JunkCategory>) -> JunkReport {
        JunkReport(volume: volume, items: items.filter { categories.contains($0.category) }, unreadableFolders: unreadableFolders)
    }
}

/// Finds macOS clutter on an external volume. Names alone are not trusted: `.DS_Store` and `._`
/// files are only reported when their contents start with the matching magic bytes, so a
/// user's own file that happens to share the name is never touched.
public struct JunkScanner: Sendable {
    static let rootTemporaryNames: Set<String> = [".TemporaryItems", ".apdisk"]
    static let rootIndexNames: Set<String> = [".Spotlight-V100", ".fseventsd"]
    /// Never looked inside: trash is handled separately, the rest belong to the system.
    static let skippedRootNames: Set<String> = [".Trashes", ".DocumentRevisions-V100", ".HFS+ Private Directory Data\r", ".vol"]
    static let timeMachineMarkers: Set<String> = ["Backups.backupdb", ".com.apple.timemachine.supported", ".timemachine"]

    static let dsStoreMagic: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x42, 0x75, 0x64, 0x31] // \0\0\0\1Bud1
    static let appleDoubleMagic: [UInt8] = [0x00, 0x05, 0x16, 0x07]

    public let policy: SafetyPolicy

    public init(policy: SafetyPolicy) {
        self.policy = policy
    }

    public enum ScanError: Error, Equatable, CustomStringConvertible {
        case timeMachineVolume
        case unreadable(Int32)

        public var description: String {
            switch self {
            case .timeMachineVolume: "Reclaim doesn’t clean Time Machine backup drives."
            case .unreadable(let code): "Reclaim couldn’t read this drive (\(String(cString: strerror(code))))."
            }
        }
    }

    public func scan(volume: URL) throws -> JunkReport {
        let root = try policy.validateExternalVolume(volume)
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let rootNames: Set<String>
        do {
            rootNames = Set(try FileTree.children(of: root))
        } catch let error as POSIXError {
            throw ScanError.unreadable(error.code.rawValue)
        }
        if !rootNames.isDisjoint(with: Self.timeMachineMarkers) {
            throw ScanError.timeMachineVolume
        }

        var items: [JunkItem] = []
        var unreadable = 0
        FileTree.walk(root, onError: { _, _ in unreadable += 1 }) { entry in
            if Task.isCancelled { return .skipDescendants }
            if entry.isSymlink { return .continue }
            let url = URL(fileURLWithPath: entry.path)
            if entry.level == 1 {
                if Self.skippedRootNames.contains(entry.name) { return .skipDescendants }
                if Self.rootIndexNames.contains(entry.name) {
                    items.append(JunkItem(url: url, category: .systemIndexes, bytes: FileTree.allocatedSize(of: entry.path)))
                    return .skipDescendants
                }
                if Self.rootTemporaryNames.contains(entry.name) {
                    items.append(JunkItem(url: url, category: .temporary, bytes: FileTree.allocatedSize(of: entry.path)))
                    return .skipDescendants
                }
            }
            if entry.isRegularFile, let category = Self.fileCategory(of: url) {
                items.append(JunkItem(url: url, category: category, bytes: entry.allocatedBytes))
            }
            return .continue
        }
        return JunkReport(volume: rootURL, items: items, unreadableFolders: unreadable)
    }

    /// The category of a regular file, verified by its contents, or nil if it isn't junk.
    static func fileCategory(of url: URL) -> JunkCategory? {
        let name = url.lastPathComponent
        if name == ".DS_Store" {
            return startsWith(url, Self.dsStoreMagic) ? .finderMetadata : nil
        }
        if name.hasPrefix("._"), name.count > 2 {
            guard startsWith(url, Self.appleDoubleMagic) else { return nil }
            let companion = url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst(2))).path
            var info = stat()
            let isOrphan = lstat(companion, &info) != 0
            if isOrphan { return .appleDouble }
            guard let contents = AppleDouble.read(url.path) else { return .appleDoubleWithMetadata }
            return contents.holdsUserMetadata ? .appleDoubleWithMetadata : .appleDouble
        }
        return nil
    }

    static func startsWith(_ url: URL, _ magic: [UInt8]) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: magic.count) else { return false }
        return Array(data) == magic
    }
}

/// Deletes junk found by `JunkScanner`, re-validating every item against the volume and
/// re-checking file contents immediately before deleting.
public struct JunkCleaner: Sendable {
    public let policy: SafetyPolicy
    let remover: any FileRemoving

    public init(policy: SafetyPolicy, remover: any FileRemoving = SystemFileRemover()) {
        self.policy = policy
        self.remover = remover
    }

    public func clean(_ report: JunkReport) throws -> RemovalResult {
        let root = try policy.validateExternalVolume(report.volume)
        var result = RemovalResult()
        for item in report.items {
            do {
                // Validate, re-check and delete the very same path string.
                let path = Paths.normalized(item.url)
                let url = URL(fileURLWithPath: path)
                guard path == item.url.path else { throw SafetyPolicy.Violation.outsideRoot(path: item.url.path, root: root) }
                try policy.validateTarget(url, withinCanonicalRoot: root)
                if item.category == .finderMetadata || item.category == .appleDouble || item.category == .appleDoubleWithMetadata {
                    // Contents (and, for ._ files, metadata) may have changed since the scan.
                    guard JunkScanner.fileCategory(of: url) == item.category else { continue }
                }
                try remover.removeItem(atPath: path)
                result.removedCount += 1
                result.freedBytes += item.bytes
            } catch {
                result.failures.append(.init(url: item.url, reason: String(describing: error)))
            }
        }
        return result
    }
}
