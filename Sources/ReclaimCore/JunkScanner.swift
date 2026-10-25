import Foundation

/// Hidden files macOS leaves on drives, which clutter TVs, cameras, car stereos and Windows PCs.
public enum JunkCategory: String, CaseIterable, Sendable, Identifiable {
    /// `.DS_Store`: Finder view settings.
    case finderMetadata
    /// `._name`: AppleDouble files holding resource forks and extended attributes on non-Mac formats.
    case appleDouble
    /// `.TemporaryItems`, `.apdisk`.
    case temporary
    /// `.Spotlight-V100`, `.fseventsd`: rebuilt automatically, so only removed when asked to.
    case systemIndexes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .finderMetadata: "Finder folder settings (.DS_Store)"
        case .appleDouble: "AppleDouble files (._)"
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

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    public func count(of category: JunkCategory) -> Int { items.filter { $0.category == category }.count }

    public func filtered(to categories: Set<JunkCategory>) -> JunkReport {
        JunkReport(volume: volume, items: items.filter { categories.contains($0.category) })
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

        public var description: String { "Reclaim doesn’t clean Time Machine backup drives." }
    }

    public func scan(volume: URL) throws -> JunkReport {
        let root = try policy.validateExternalVolume(volume)
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        let rootNames = Set((try? FileTree.children(of: root)) ?? [])
        if !rootNames.isDisjoint(with: Self.timeMachineMarkers) {
            throw ScanError.timeMachineVolume
        }

        var items: [JunkItem] = []
        FileTree.walk(root) { entry in
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
        return JunkReport(volume: rootURL, items: items)
    }

    /// The category of a regular file, verified by its contents, or nil if it isn't junk.
    static func fileCategory(of url: URL) -> JunkCategory? {
        let name = url.lastPathComponent
        if name == ".DS_Store" {
            return startsWith(url, Self.dsStoreMagic) ? .finderMetadata : nil
        }
        if name.hasPrefix("._"), name.count > 2 {
            return startsWith(url, Self.appleDoubleMagic) ? .appleDouble : nil
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
                try policy.validateTarget(item.url, withinCanonicalRoot: root)
                if item.category == .finderMetadata || item.category == .appleDouble {
                    guard JunkScanner.fileCategory(of: item.url) == item.category else { continue }
                }
                try remover.removeItem(atPath: item.url.path)
                result.removedCount += 1
                result.freedBytes += item.bytes
            } catch {
                result.failures.append(.init(url: item.url, reason: String(describing: error)))
            }
        }
        return result
    }
}
