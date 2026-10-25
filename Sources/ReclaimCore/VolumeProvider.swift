import Foundation

public protocol VolumeProviding: Sendable {
    func mountedDrives() -> [DriveInfo]
}

/// Lists the drives a user would see in Finder's sidebar: the boot drive plus anything mounted
/// under /Volumes. System volumes (Preboot, Recovery, VM, Data) are skipped.
public struct VolumeProvider: VolumeProviding {
    public let mode: RuntimeMode

    public init(mode: RuntimeMode) {
        self.mode = mode
    }

    static let resourceKeys: [URLResourceKey] = [
        .volumeLocalizedNameKey, .volumeNameKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsLocalKey,
        .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        .volumeTypeNameKey, .volumeUUIDStringKey,
    ]

    public func mountedDrives() -> [DriveInfo] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Self.resourceKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls
            .filter { Self.isUserFacing(path: $0.path, mode: mode) }
            .compactMap(Self.drive(at:))
            .sorted(by: Self.displayOrder)
    }

    static func isUserFacing(path: String, mode: RuntimeMode) -> Bool {
        switch mode {
        case .live:
            return path == "/" || (path.hasPrefix("/Volumes/") && !path.dropFirst("/Volumes/".count).contains("/"))
        case .sandbox:
            return path.hasPrefix("/Volumes/" + RuntimeMode.sandboxVolumePrefix)
                && !path.dropFirst("/Volumes/".count).contains("/")
        }
    }

    /// Boot drive first, then internal, then external, each alphabetically.
    static func displayOrder(_ a: DriveInfo, _ b: DriveInfo) -> Bool {
        func rank(_ d: DriveInfo) -> Int { d.isBoot ? 0 : (d.isInternal ? 1 : 2) }
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    static func drive(at url: URL) -> DriveInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
              values.volumeIsBrowsable != false,
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        return DriveInfo(
            url: url,
            name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
            totalBytes: Int64(total),
            freeBytes: Int64(values.volumeAvailableCapacity ?? 0),
            importantFreeBytes: values.volumeAvailableCapacityForImportantUsage,
            isBoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
            isInternal: values.volumeIsInternal ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isNetwork: !(values.volumeIsLocal ?? true),
            isReadOnly: values.volumeIsReadOnly ?? false,
            fileSystem: values.volumeTypeName,
            uuid: values.volumeUUIDString
        )
    }
}
