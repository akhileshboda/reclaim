import AppKit
import Foundation
import Observation
import ReclaimCore

/// One drive as shown in the panel.
public struct DriveState: Sendable, Identifiable, Equatable {
    public var id: String { drive.id }
    public let drive: DriveInfo
    public let trashURL: URL?
    public let trash: TrashSummary

    public init(drive: DriveInfo, trashURL: URL?, trash: TrashSummary) {
        self.drive = drive
        self.trashURL = trashURL
        self.trash = trash
    }

    public var breakdown: SpaceBreakdown { SpaceBreakdown(drive: drive, trashBytes: trash.totalBytes) }
    public var canEmpty: Bool { trashURL != nil && trash.access == .readable && (trash.itemCount > 0 || trash.totalBytes > 0) }
}

/// A short message shown at the bottom of the panel after an action.
public struct Notice: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable { case success, warning }
    public let id = UUID()
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public static func == (a: Notice, b: Notice) -> Bool { a.id == b.id }
}

/// Everything the panel shows and every action it can take. Lives on the main actor; slow
/// filesystem work runs in detached tasks.
@MainActor @Observable
public final class AppModel {
    public enum Activity: Sendable, Equatable { case emptying, deleting }

    public private(set) var drives: [DriveState] = []
    public private(set) var activity: [String: Activity] = [:]
    public private(set) var hasLoaded = false
    public private(set) var isRefreshing = false
    public var notice: Notice?

    public let mode: RuntimeMode
    public let settings: AppSettings

    @ObservationIgnored let provider: any VolumeProviding
    @ObservationIgnored let locator: TrashLocator
    @ObservationIgnored let scanner: any TrashScanning
    @ObservationIgnored let emptier: TrashEmptier
    @ObservationIgnored let confirmer: any Confirming
    @ObservationIgnored private var refreshQueued = false

    public init(
        mode: RuntimeMode,
        settings: AppSettings,
        confirmer: any Confirming,
        provider: (any VolumeProviding)? = nil,
        locator: TrashLocator? = nil,
        scanner: any TrashScanning = TrashScanner(),
        policy: SafetyPolicy? = nil
    ) {
        self.mode = mode
        self.settings = settings
        self.confirmer = confirmer
        self.provider = provider ?? VolumeProvider(mode: mode)
        self.locator = locator ?? TrashLocator(mode: mode)
        self.scanner = scanner
        self.emptier = TrashEmptier(policy: policy ?? SafetyPolicy(mode: mode))
    }

    // MARK: Derived state

    public var totalReclaimable: Int64 { drives.reduce(0) { $0 + $1.trash.totalBytes } }
    public var emptiableDrives: [DriveState] { drives.filter(\.canEmpty) }
    public var needsFullDiskAccess: Bool { drives.contains { $0.trash.access == .denied } }
    public var badgeText: String? { settings.badgeMode.text(reclaimable: totalReclaimable) }

    public func state(for id: String) -> DriveState? { drives.first { $0.id == id } }

    // MARK: Refresh

    /// Re-reads mounted drives and measures every trash folder. Calls made while a refresh is
    /// running are coalesced into one follow-up refresh.
    public func refresh() async {
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            let provider = provider, locator = locator, scanner = scanner
            drives = await Task.detached(priority: .userInitiated) {
                provider.mountedDrives().map { drive in
                    let trashURL = locator.trashURL(for: drive)
                    let trash = trashURL.map { scanner.scan(root: $0, largestCount: 20) } ?? .empty
                    return DriveState(drive: drive, trashURL: trashURL, trash: trash)
                }
            }.value
            hasLoaded = true
        } while refreshQueued
    }

    // MARK: Emptying

    public func emptyTrash(driveID: String) async {
        guard let state = state(for: driveID), state.canEmpty, activity[driveID] == nil else { return }
        if settings.askBeforeEmptying {
            let request = ConfirmationRequest.emptyTrash(driveName: state.drive.name, itemCount: state.trash.itemCount, bytes: state.trash.totalBytes)
            guard await confirmer.confirm(request) else { return }
        }
        let result = await empty(state)
        await refresh()
        notice = Self.notice(for: result, scope: "on “\(state.drive.name)”")
    }

    public func emptyAllTrash() async {
        let targets = emptiableDrives.filter { activity[$0.id] == nil }
        guard !targets.isEmpty else { return }
        if settings.askBeforeEmptying {
            let request: ConfirmationRequest
            if let only = targets.first, targets.count == 1 {
                request = .emptyTrash(driveName: only.drive.name, itemCount: only.trash.itemCount, bytes: only.trash.totalBytes)
            } else {
                request = .emptyAllTrash(
                    driveCount: targets.count,
                    itemCount: targets.reduce(0) { $0 + $1.trash.itemCount },
                    bytes: targets.reduce(0) { $0 + $1.trash.totalBytes }
                )
            }
            guard await confirmer.confirm(request) else { return }
        }
        var combined = RemovalResult()
        for target in targets {
            combined.merge(await empty(target))
        }
        await refresh()
        notice = Self.notice(for: combined, scope: targets.count == 1 ? "on “\(targets[0].drive.name)”" : "on \(targets.count) drives")
    }

    /// Permanently deletes specific items from a drive's trash (Trash peek).
    public func deleteItems(_ items: [TrashItem], driveID: String) async {
        guard let state = state(for: driveID), let trashURL = state.trashURL, !items.isEmpty, activity[driveID] == nil else { return }
        if settings.askBeforeEmptying {
            let request = ConfirmationRequest.deleteItems(names: items.map(\.name), bytes: items.reduce(0) { $0 + $1.bytes })
            guard await confirmer.confirm(request) else { return }
        }
        activity[driveID] = .deleting
        let emptier = emptier, urls = items.map(\.url)
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try emptier.removeItems(urls, fromTrashAt: trashURL) }
        }.value
        activity[driveID] = nil
        await refresh()
        notice = Self.notice(for: outcome, scope: "from the Trash")
    }

    public func reveal(_ item: TrashItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func empty(_ state: DriveState) async -> RemovalResult {
        guard let trashURL = state.trashURL else { return RemovalResult() }
        activity[state.id] = .emptying
        defer { activity[state.id] = nil }
        let emptier = emptier
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try emptier.emptyTrash(at: trashURL) }
        }.value
        switch outcome {
        case .success(let result):
            return result
        case .failure(let error):
            var result = RemovalResult()
            result.failures = [.init(url: trashURL, reason: String(describing: error))]
            return result
        }
    }

    private static func notice(for outcome: Result<RemovalResult, any Error>, scope: String) -> Notice {
        switch outcome {
        case .success(let result): notice(for: result, scope: scope)
        case .failure(let error): Notice(kind: .warning, text: String(describing: error))
        }
    }

    static func notice(for result: RemovalResult, scope: String) -> Notice {
        let freed = ByteFormat.string(result.freedBytes)
        if result.failures.isEmpty {
            return Notice(kind: .success, text: "Reclaimed \(freed) \(scope).")
        }
        let count = result.failures.count
        return Notice(kind: .warning, text: "Reclaimed \(freed) \(scope). \(count) \(count == 1 ? "item" : "items") couldn’t be erased.")
    }
}
