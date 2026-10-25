import Foundation

/// How a drive's capacity divides into the four segments Reclaim shows.
///
/// - free: available right now.
/// - purgeable: caches and snapshots macOS frees automatically when space runs low.
/// - trash: what the user deleted but hasn't emptied. This is what Reclaim gets back.
/// - used: everything else.
///
/// The segments always sum to `total`.
public struct SpaceBreakdown: Sendable, Equatable {
    public let total: Int64
    public let used: Int64
    public let trash: Int64
    public let purgeable: Int64
    public let free: Int64

    public init(total: Int64, free: Int64, importantFree: Int64?, trash: Int64) {
        let total = max(0, total)
        let free = min(max(0, free), total)
        let purgeable = min(max(0, (importantFree ?? free) - free), total - free)
        let trash = min(max(0, trash), total - free - purgeable)
        self.total = total
        self.free = free
        self.purgeable = purgeable
        self.trash = trash
        self.used = total - free - purgeable - trash
    }

    public init(drive: DriveInfo, trashBytes: Int64) {
        self.init(total: drive.totalBytes, free: drive.freeBytes, importantFree: drive.importantFreeBytes, trash: trashBytes)
    }

    /// Space the user can get back by emptying the trash.
    public var reclaimable: Int64 { trash }

    /// Free space once the trash is emptied and macOS purges what it can.
    public var availableAfterCleanup: Int64 { free + purgeable + trash }

    public func fraction(of segment: Int64) -> Double {
        total > 0 ? Double(segment) / Double(total) : 0
    }
}
