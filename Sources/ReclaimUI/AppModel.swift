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

/// Unmounts and ejects a drive. The app uses NSWorkspace; tests use a fake.
public protocol DriveEjecting: Sendable {
    func eject(_ volume: URL) throws
}

public struct WorkspaceEjector: DriveEjecting {
    public init() {}
    public func eject(_ volume: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
    }
}

/// Delivers low-space warnings (a user notification in the app, a log line in sandbox mode).
@MainActor
public protocol LowSpaceNotifying: AnyObject {
    func notify(title: String, body: String)
}

/// Everything the panel shows and every action it can take. Lives on the main actor; slow
/// filesystem work runs in detached tasks.
@MainActor @Observable
public final class AppModel {
    public enum Activity: Sendable, Equatable { case emptying, deleting, scanningJunk, cleaningJunk, ejecting }

    public private(set) var drives: [DriveState] = []
    public private(set) var activity: [String: Activity] = [:]
    public private(set) var hasLoaded = false
    public private(set) var isRefreshing = false
    public var notice: Notice?
    /// A newer release found by the update checker.
    public var availableUpdate: Release?

    public let mode: RuntimeMode
    public let settings: AppSettings

    @ObservationIgnored let provider: any VolumeProviding
    @ObservationIgnored let locator: TrashLocator
    @ObservationIgnored let scanner: any TrashScanning
    @ObservationIgnored let emptier: TrashEmptier
    @ObservationIgnored let policy: SafetyPolicy
    @ObservationIgnored let ejector: any DriveEjecting
    @ObservationIgnored let confirmer: any Confirming
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var pendingRescan: Set<String>? = []
    @ObservationIgnored public weak var lowSpaceNotifier: (any LowSpaceNotifying)?
    @ObservationIgnored private var lowSpaceTracker = LowSpaceTracker(thresholdPercent: 10)

    public init(
        mode: RuntimeMode,
        settings: AppSettings,
        confirmer: any Confirming,
        provider: (any VolumeProviding)? = nil,
        locator: TrashLocator? = nil,
        scanner: any TrashScanning = TrashScanner(),
        policy: SafetyPolicy? = nil,
        ejector: any DriveEjecting = WorkspaceEjector()
    ) {
        let policy = policy ?? SafetyPolicy(mode: mode)
        self.mode = mode
        self.settings = settings
        self.confirmer = confirmer
        self.provider = provider ?? VolumeProvider(mode: mode)
        self.locator = locator ?? TrashLocator(mode: mode)
        self.scanner = scanner
        self.policy = policy
        self.emptier = TrashEmptier(policy: policy)
        self.ejector = ejector
    }

    // MARK: Derived state

    public var totalReclaimable: Int64 { drives.reduce(0) { $0 + $1.trash.totalBytes } }
    public var emptiableDrives: [DriveState] { drives.filter(\.canEmpty) }
    public var needsFullDiskAccess: Bool { drives.contains { $0.trash.access == .denied } }
    public var badgeText: String? { settings.badgeMode.text(reclaimable: totalReclaimable) }

    public func state(for id: String) -> DriveState? { drives.first { $0.id == id } }

    // MARK: Refresh

    /// Re-reads mounted drives and their capacities, and measures Trash folders.
    ///
    /// - Parameter driveIDs: which drives' Trash to rescan. `nil` rescans every drive; an empty
    ///   set only refreshes capacities and keeps the last Trash measurements, which avoids waking
    ///   sleeping hard drives. New drives are always scanned.
    ///
    /// Calls made while a refresh is running are merged into one follow-up refresh.
    public func refresh(rescanning driveIDs: Set<String>? = nil) async {
        pendingRescan = Self.merge(pendingRescan, driveIDs)
        if isRefreshing {
            refreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshQueued = false
            let rescan = pendingRescan
            pendingRescan = []
            let previous = Dictionary(drives.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let provider = provider, locator = locator, scanner = scanner
            drives = await Task.detached(priority: .userInitiated) {
                provider.mountedDrives().map { drive in
                    let trashURL = locator.trashURL(for: drive)
                    if let rescan, !rescan.contains(drive.id), let old = previous[drive.id], old.trashURL == trashURL {
                        return DriveState(drive: drive, trashURL: trashURL, trash: old.trash)
                    }
                    let trash = trashURL.map { scanner.scan(root: $0, largestCount: 20) } ?? .empty
                    return DriveState(drive: drive, trashURL: trashURL, trash: trash)
                }
            }.value
            hasLoaded = true
        } while refreshQueued
        checkLowSpace()
    }

    /// `nil` means "everything" and absorbs any set.
    static func merge(_ a: Set<String>?, _ b: Set<String>?) -> Set<String>? {
        guard let a, let b else { return nil }
        return a.union(b)
    }

    /// The drives whose Trash contains any of `paths` (from the file-system watcher).
    public func driveIDs(containing paths: [String]) -> Set<String> {
        var ids: Set<String> = []
        for state in drives {
            guard let trash = state.trashURL?.path else { continue }
            if paths.contains(where: { $0 == trash || $0.hasPrefix(trash + "/") }) { ids.insert(state.id) }
        }
        return ids
    }

    /// Trash folders worth watching: the ones Reclaim can read.
    public var watchableTrashPaths: [String] {
        drives.filter { $0.trash.access == .readable }.compactMap { $0.trashURL?.path }
    }

    private func checkLowSpace() {
        guard settings.lowSpaceAlerts, let notifier = lowSpaceNotifier else { return }
        lowSpaceTracker.thresholdPercent = settings.lowSpacePercent
        let alerts = lowSpaceTracker.evaluate(drives.map { ($0.id, $0.drive.name, $0.breakdown, $0.drive.isReadOnly) })
        for alert in alerts {
            let message = LowSpaceTracker.message(for: alert)
            notifier.notify(title: message.title, body: message.body)
        }
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

    public func revealDrive(driveID: String) {
        guard let state = state(for: driveID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([state.drive.url])
    }

    // MARK: Eject

    public func canEject(_ state: DriveState) -> Bool {
        state.drive.isEjectable && !state.drive.isBoot && (try? policy.validateExternalVolume(state.drive.url)) != nil
    }

    public func eject(driveID: String) async {
        guard let state = state(for: driveID), canEject(state), activity[driveID] == nil else { return }
        activity[driveID] = .ejecting
        let ejector = ejector, url = state.drive.url
        let outcome = await Task.detached(priority: .userInitiated) { Result { try ejector.eject(url) } }.value
        activity[driveID] = nil
        await refresh()
        switch outcome {
        case .success:
            notice = Notice(kind: .success, text: "“\(state.drive.name)” was ejected. You can unplug it now.")
        case .failure(let error):
            notice = Notice(kind: .warning, text: "“\(state.drive.name)” couldn’t be ejected. \(error.localizedDescription)")
        }
    }

    // MARK: Hidden junk

    public func canCleanJunk(_ state: DriveState) -> Bool {
        state.drive.isExternal && !state.drive.isReadOnly && (try? policy.validateExternalVolume(state.drive.url)) != nil
    }

    /// Finds hidden macOS files on a drive, asks once with a summary, then removes them.
    public func cleanJunk(driveID: String) async {
        guard let state = state(for: driveID), canCleanJunk(state), activity[driveID] == nil else { return }
        activity[driveID] = .scanningJunk
        let scanner = JunkScanner(policy: policy), volume = state.drive.url
        var categories: Set<JunkCategory> = [.finderMetadata, .appleDouble, .temporary]
        if settings.includeSystemJunk { categories.insert(.systemIndexes) }
        let scanned = await Task.detached(priority: .userInitiated) {
            Result { try scanner.scan(volume: volume).filtered(to: categories) }
        }.value
        activity[driveID] = nil

        let report: JunkReport
        switch scanned {
        case .failure(let error):
            notice = Notice(kind: .warning, text: String(describing: error))
            return
        case .success(let found):
            report = found
        }
        guard !report.items.isEmpty else {
            notice = Notice(kind: .success, text: "No hidden macOS files on “\(state.drive.name)”.")
            return
        }
        let request = ConfirmationRequest.cleanJunk(driveName: state.drive.name, fileCount: report.items.count, bytes: report.totalBytes)
        guard await confirmer.confirm(request) else { return }

        activity[driveID] = .cleaningJunk
        let cleaner = JunkCleaner(policy: policy)
        let outcome = await Task.detached(priority: .userInitiated) { Result { try cleaner.clean(report) } }.value
        activity[driveID] = nil
        await refresh()
        switch outcome {
        case .success(let result) where result.failures.isEmpty:
            notice = Notice(kind: .success, text: "Removed \(result.removedCount.formatted()) hidden files from “\(state.drive.name)”.")
        case .success(let result):
            notice = Notice(kind: .warning, text: "Removed \(result.removedCount.formatted()) hidden files from “\(state.drive.name)”. \(result.failures.count) couldn’t be removed.")
        case .failure(let error):
            notice = Notice(kind: .warning, text: String(describing: error))
        }
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
