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
    /// Space came back: the panel shows the boomerang instead of a checkmark.
    public let reclaimedSpace: Bool

    public init(kind: Kind, text: String, reclaimedSpace: Bool = false) {
        self.kind = kind
        self.text = text
        self.reclaimedSpace = reclaimedSpace
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
    func notify(driveID: String, title: String, body: String)
}

/// Asks a drive row to open its Trash peek (e.g. after clicking a low-space notification).
public struct PeekRequest: Equatable, Sendable {
    public let driveID: String
    let token = UUID()
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
    /// The result of the last action. Stays until dismissed or the panel closes, and is
    /// announced to VoiceOver.
    public var notice: Notice? {
        didSet {
            guard let notice, notice != oldValue, let app = NSApp else { return }
            NSAccessibility.post(element: app, notification: .announcementRequested, userInfo: [
                .announcement: notice.text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }
    /// A newer release found by the update checker.
    public var availableUpdate: Release?
    /// The latest request to expand a drive's Trash peek.
    public var peekRequest: PeekRequest?

    public func showTrashPeek(driveID: String) {
        peekRequest = PeekRequest(driveID: driveID)
    }

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
    /// The startup disk's Trash is unreadable: that needs Full Disk Access.
    public var needsFullDiskAccess: Bool { drives.contains { $0.drive.isBoot && $0.trash.access == .denied } }

    /// Opens the Privacy & Security pane that grants access to this drive's Trash: Full Disk
    /// Access for the startup disk, Files & Folders (Removable Volumes) for anything else. macOS
    /// asks about removable volumes only once, so a "Don't Allow" has to be undone there.
    public func openPrivacySettings(for state: DriveState) {
        let pane = state.drive.isBoot ? "Privacy_AllFiles" : "Privacy_FilesAndFolders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
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
    /// Drives that are mid-action are skipped: the action refreshes them itself when it finishes.
    public func driveIDs(containing paths: [String]) -> Set<String> {
        let paths = paths.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 }
        var ids: Set<String> = []
        for state in drives where activity[state.id] == nil {
            guard let watched = Self.watchedPath(for: state) else { continue }
            if paths.contains(where: { $0 == watched || $0.hasPrefix(watched + "/") }) { ids.insert(state.id) }
        }
        return ids
    }

    /// Folders worth watching: each readable Trash folder, and for an external drive that has no
    /// Trash folder yet, the drive itself, so the first deletion on it is noticed.
    public var watchableTrashPaths: [String] {
        // A closure, not `compactMap(Self.watchedPath(for:))`: Swift 6.0 compilers can't see that a
        // main-actor method reference is safe here.
        drives.compactMap { Self.watchedPath(for: $0) }
    }

    static func watchedPath(for state: DriveState) -> String? {
        switch state.trash.access {
        case .readable: state.trashURL?.path
        case .unavailable where state.trashURL != nil && !state.drive.isBoot: state.drive.url.path
        default: nil
        }
    }

    /// Drives whose Trash isn't kept fresh by the file-system watcher.
    public var unwatchedDriveIDs: Set<String> {
        Set(drives.filter { Self.watchedPath(for: $0) == nil }.map(\.id))
    }

    private func checkLowSpace() {
        guard settings.lowSpaceAlerts, let notifier = lowSpaceNotifier else { return }
        lowSpaceTracker.thresholdPercent = settings.lowSpacePercent
        let alerts = lowSpaceTracker.evaluate(drives.map { ($0.id, $0.drive.name, $0.breakdown, $0.drive.isReadOnly) })
        for alert in alerts {
            let message = LowSpaceTracker.message(for: alert)
            notifier.notify(driveID: alert.driveID, title: message.title, body: message.body)
        }
    }

    // MARK: Emptying

    public func emptyTrash(driveID: String) async {
        guard let state = state(for: driveID), state.canEmpty, activity[driveID] == nil else { return }
        if settings.askBeforeEmptying {
            let request = ConfirmationRequest.emptyTrash(driveName: state.drive.name, itemCount: state.trash.itemCount, bytes: state.trash.totalBytes)
            guard await confirmer.confirm(request) else { return }
        }
        guard let confirmed = unchanged(state) else { return }
        let outcome = await empty(confirmed)
        await refresh()
        notice = Self.notice(for: [(state.drive.name, outcome)], scope: "on “\(state.drive.name)”")
    }

    /// The drive as it is now, if it's still the one the person confirmed. The alert runs a
    /// nested event loop, so drives can be ejected or swapped (same name, same path) meanwhile.
    private func unchanged(_ confirmed: DriveState) -> DriveState? {
        guard let current = state(for: confirmed.id),
              current.drive.uuid == confirmed.drive.uuid,
              current.trashURL == confirmed.trashURL,
              activity[confirmed.id] == nil
        else {
            notice = Notice(kind: .warning, text: "“\(confirmed.drive.name)” changed while Reclaim was asking. Nothing was erased.")
            return nil
        }
        return current
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
                    driveNames: targets.map(\.drive.name),
                    itemCount: targets.reduce(0) { $0 + $1.trash.itemCount },
                    bytes: targets.reduce(0) { $0 + $1.trash.totalBytes }
                )
            }
            guard await confirmer.confirm(request) else { return }
        }
        var outcomes: [(String, Result<RemovalResult, any Error>)] = []
        for target in targets {
            guard let confirmed = unchanged(target) else { return }
            outcomes.append((target.drive.name, await empty(confirmed)))
        }
        await refresh()
        notice = Self.notice(for: outcomes, scope: targets.count == 1 ? "on “\(targets[0].drive.name)”" : "on \(targets.count) drives")
    }

    /// Permanently deletes specific items from a drive's trash (Trash peek). Always confirmed,
    /// like Finder's Delete Immediately…, whatever the "Ask before emptying" setting says.
    public func deleteItems(_ items: [TrashItem], driveID: String) async {
        guard let state = state(for: driveID), let trashURL = state.trashURL, !items.isEmpty, activity[driveID] == nil else { return }
        let request = ConfirmationRequest.deleteItems(names: items.map(\.name), bytes: items.reduce(0) { $0 + $1.bytes })
        guard await confirmer.confirm(request) else { return }
        guard unchanged(state) != nil else { return }
        activity[driveID] = .deleting
        // Take each item's "._" AppleDouble companion with it, or it would appear as a new item.
        let companions = items.map { $0.url.deletingLastPathComponent().appendingPathComponent("._" + $0.name) }
            .filter { Paths.exists($0.path) }
        let emptier = emptier, urls = items.map(\.url) + companions
        let outcome = await Task.detached(priority: .userInitiated) {
            Result { try emptier.removeItems(urls, fromTrashAt: trashURL) }
        }.value
        activity[driveID] = nil
        await refresh()
        notice = Self.notice(for: [(state.drive.name, outcome)], scope: "from the Trash on “\(state.drive.name)”")
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
        state.drive.canEject && (try? policy.validateExternalVolume(state.drive.url)) != nil
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
        var categories = JunkReport.defaultCategories
        if settings.includeSystemJunk { categories.insert(.systemIndexes) }
        let scanned = await Task.detached(priority: .userInitiated) {
            Result { try scanner.scan(volume: volume) }
        }.value
        activity[driveID] = nil

        let full: JunkReport
        switch scanned {
        case .failure(let error):
            notice = Notice(kind: .warning, text: UserMessage.describe(error, driveName: state.drive.name))
            return
        case .success(let found):
            full = found
        }
        let report = full.filtered(to: categories)
        let kept = full.count(of: .appleDoubleWithMetadata)
        guard !report.items.isEmpty else {
            var text = "No hidden macOS files to remove on “\(state.drive.name)”."
            if kept > 0 { text += " \(kept.formatted()) ._ files hold Finder tags or other metadata and were kept." }
            notice = Notice(kind: .success, text: text)
            return
        }
        let request = ConfirmationRequest.cleanJunk(driveName: state.drive.name, fileCount: report.items.count, bytes: report.totalBytes, keptWithMetadata: kept)
        guard await confirmer.confirm(request) else { return }

        activity[driveID] = .cleaningJunk
        let cleaner = JunkCleaner(policy: policy)
        let outcome = await Task.detached(priority: .userInitiated) { Result { try cleaner.clean(report) } }.value
        activity[driveID] = nil
        await refresh()
        switch outcome {
        case .success(let result):
            var text = "Removed \(result.removedCount.formatted()) hidden files from “\(state.drive.name)”."
            if !result.failures.isEmpty { text += " \(result.failures.count.formatted()) couldn’t be removed." }
            if report.unreadableFolders > 0 { text += " \(report.unreadableFolders.formatted()) folders couldn’t be read and were skipped." }
            let clean = result.failures.isEmpty && report.unreadableFolders == 0
            notice = Notice(kind: clean ? .success : .warning, text: text)
        case .failure(let error):
            notice = Notice(kind: .warning, text: UserMessage.describe(error, driveName: state.drive.name))
        }
    }

    private func empty(_ state: DriveState) async -> Result<RemovalResult, any Error> {
        guard let trashURL = state.trashURL else { return .success(RemovalResult()) }
        activity[state.id] = .emptying
        defer { activity[state.id] = nil }
        let emptier = emptier
        return await Task.detached(priority: .userInitiated) {
            Result { try emptier.emptyTrash(at: trashURL) }
        }.value
    }

    static func notice(for outcomes: [(driveName: String, outcome: Result<RemovalResult, any Error>)], scope: String) -> Notice {
        var combined = RemovalResult()
        var errors: [String] = []
        for (driveName, outcome) in outcomes {
            switch outcome {
            case .success(let result): combined.merge(result)
            case .failure(let error): errors.append(UserMessage.describe(error, driveName: driveName))
            }
        }
        if combined.removedCount == 0, let first = errors.first {
            return Notice(kind: .warning, text: first)
        }
        if combined.removedCount == 0, !combined.failures.isEmpty {
            return Notice(kind: .warning, text: failureText(combined.failures))
        }
        var text = "Reclaimed \(ByteFormat.string(combined.freedBytes)) \(scope)."
        if !combined.failures.isEmpty { text += " " + failureText(combined.failures) }
        if let first = errors.first { text += " " + first }
        let clean = combined.failures.isEmpty && errors.isEmpty
        return Notice(kind: clean ? .success : .warning, text: text, reclaimedSpace: clean)
    }

    /// Says how many items were left behind and the macOS reason for the first one, so the
    /// person knows what to fix instead of guessing.
    static func failureText(_ failures: [RemovalResult.Failure]) -> String {
        let count = failures.count
        var reason = failures.first?.reason.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reason.isEmpty, !reason.hasSuffix(".") { reason += "." }
        let subject = "\(count.formatted()) \(count == 1 ? "item" : "items") couldn’t be erased."
        return reason.isEmpty ? subject : "\(subject) First problem: \(reason)"
    }
}
