import Foundation
import Observation
import ReclaimCore

/// Where settings are persisted. `UserDefaults` in the real app; in-memory for tests and sandbox
/// mode, so automated runs never write preference files into the user's Library.
public protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: SettingsStore {}

public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]
    public init() {}
    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// User preferences.
@MainActor @Observable
public final class AppSettings {
    enum Key {
        static let askBeforeEmptying = "askBeforeEmptying"
        static let badgeMode = "badgeMode"
        static let lowSpaceAlerts = "lowSpaceAlerts"
        static let lowSpacePercent = "lowSpacePercent"
        static let checkForUpdates = "checkForUpdates"
        static let includeSystemJunk = "includeSystemJunk"
        static let openPanelShortcut = "openPanelShortcut"
        static let fullDiskAccessBannerDismissed = "fullDiskAccessBannerDismissed"
        static let lowSpaceAlertedAt = "lowSpaceAlertedAt"
    }

    @ObservationIgnored private let store: any SettingsStore

    public var askBeforeEmptying: Bool {
        didSet { store.set(askBeforeEmptying, forKey: Key.askBeforeEmptying) }
    }

    public var badgeMode: BadgeMode {
        didSet { store.set(badgeMode.rawValue, forKey: Key.badgeMode) }
    }

    public var lowSpaceAlerts: Bool {
        didSet { store.set(lowSpaceAlerts, forKey: Key.lowSpaceAlerts) }
    }

    /// Alert when free + purgeable space drops below this share of a drive.
    public var lowSpacePercent: Int {
        didSet { store.set(lowSpacePercent, forKey: Key.lowSpacePercent) }
    }

    public var checkForUpdates: Bool {
        didSet { store.set(checkForUpdates, forKey: Key.checkForUpdates) }
    }

    /// Also remove Spotlight indexes and FSEvents logs when cleaning hidden files.
    public var includeSystemJunk: Bool {
        didSet { store.set(includeSystemJunk, forKey: Key.includeSystemJunk) }
    }

    /// Global shortcut that opens the panel; nil when the user removed it.
    public var openPanelShortcut: Shortcut? {
        didSet {
            // An empty value records "removed", so the default doesn't come back on relaunch.
            store.set(openPanelShortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: Key.openPanelShortcut)
        }
    }

    /// The person chose "Not Now" on the Full Disk Access banner; rows still show a lock line.
    public var fullDiskAccessBannerDismissed: Bool {
        didSet { store.set(fullDiskAccessBannerDismissed, forKey: Key.fullDiskAccessBannerDismissed) }
    }

    /// When each drive was last warned that it's almost full (drive ID → date).
    public var lowSpaceAlertedAt: [String: Date] {
        get {
            let raw = store.object(forKey: Key.lowSpaceAlertedAt) as? [String: Double] ?? [:]
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            guard newValue != lowSpaceAlertedAt else { return }
            store.set(newValue.mapValues(\.timeIntervalSince1970), forKey: Key.lowSpaceAlertedAt)
        }
    }

    /// Set by the app when the chosen shortcut couldn't be registered (another app owns it).
    /// Not persisted.
    public var shortcutUnavailable = false

    public init(store: any SettingsStore = UserDefaults.standard) {
        self.store = store
        askBeforeEmptying = store.object(forKey: Key.askBeforeEmptying) as? Bool ?? true
        badgeMode = (store.object(forKey: Key.badgeMode) as? String).flatMap(BadgeMode.init(rawValue:)) ?? .automatic
        lowSpaceAlerts = store.object(forKey: Key.lowSpaceAlerts) as? Bool ?? true
        lowSpacePercent = store.object(forKey: Key.lowSpacePercent) as? Int ?? 10
        checkForUpdates = store.object(forKey: Key.checkForUpdates) as? Bool ?? true
        includeSystemJunk = store.object(forKey: Key.includeSystemJunk) as? Bool ?? false
        fullDiskAccessBannerDismissed = store.object(forKey: Key.fullDiskAccessBannerDismissed) as? Bool ?? false
        if let data = store.object(forKey: Key.openPanelShortcut) as? Data {
            openPanelShortcut = try? JSONDecoder().decode(Shortcut.self, from: data)
        } else {
            openPanelShortcut = .defaultOpenPanel
        }
    }
}
