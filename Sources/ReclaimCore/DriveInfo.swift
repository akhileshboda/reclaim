import Foundation

/// A snapshot of one mounted volume as the user sees it in Finder.
public struct DriveInfo: Sendable, Identifiable, Hashable {
    public var id: String { url.path }

    public let url: URL
    public let name: String
    public let totalBytes: Int64
    /// Bytes that are free right now (`volumeAvailableCapacity`).
    public let freeBytes: Int64
    /// Free bytes plus space macOS can purge on demand (`volumeAvailableCapacityForImportantUsage`).
    /// `nil` on file systems that don't report it.
    public let importantFreeBytes: Int64?
    public let isBoot: Bool
    public let isInternal: Bool
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isNetwork: Bool
    public let isReadOnly: Bool
    public let fileSystem: String?
    public let uuid: String?

    public init(
        url: URL,
        name: String,
        totalBytes: Int64,
        freeBytes: Int64,
        importantFreeBytes: Int64? = nil,
        isBoot: Bool = false,
        isInternal: Bool = false,
        isRemovable: Bool = false,
        isEjectable: Bool = false,
        isNetwork: Bool = false,
        isReadOnly: Bool = false,
        fileSystem: String? = nil,
        uuid: String? = nil
    ) {
        self.url = url
        self.name = name
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.importantFreeBytes = importantFreeBytes
        self.isBoot = isBoot
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isNetwork = isNetwork
        self.isReadOnly = isReadOnly
        self.fileSystem = fileSystem
        self.uuid = uuid
    }

    /// External drives are the ones junk cleanup and eject apply to.
    public var isExternal: Bool { !isBoot && !isInternal }

    /// Whether the panel offers Eject. `isEjectable` alone isn't enough: many USB hard drives and
    /// enclosures report themselves as fixed media, so macOS says "not ejectable" even though
    /// Finder ejects them fine. Any external drive qualifies; the boot drive never does.
    public var canEject: Bool { !isBoot && (isEjectable || isExternal) }
}
