import SwiftUI
import ReclaimCore

/// System services the Settings panes need from the app shell.
public struct SettingsServices {
    /// nil when launch at login can't be changed (sandbox mode).
    public var launchAtLogin: Binding<Bool>?
    public var launchAtLoginNote: String?
    public var fullDiskAccessGranted: Bool
    public var openFullDiskAccessSettings: () -> Void
    public var checkForUpdatesNow: () -> Void
    public var version: String

    public init(
        launchAtLogin: Binding<Bool>?,
        launchAtLoginNote: String? = nil,
        fullDiskAccessGranted: Bool,
        openFullDiskAccessSettings: @escaping () -> Void = {},
        checkForUpdatesNow: @escaping () -> Void = {},
        version: String
    ) {
        self.launchAtLogin = launchAtLogin
        self.launchAtLoginNote = launchAtLoginNote
        self.fullDiskAccessGranted = fullDiskAccessGranted
        self.openFullDiskAccessSettings = openFullDiskAccessSettings
        self.checkForUpdatesNow = checkForUpdatesNow
        self.version = version
    }
}

public struct GeneralSettingsPane: View {
    @Bindable var settings: AppSettings
    let services: SettingsServices
    @State private var shortcutProblem: String?

    public init(settings: AppSettings, services: SettingsServices) {
        self.settings = settings
        self.services = services
    }

    public var body: some View {
        Form {
            Section {
                if let launchAtLogin = services.launchAtLogin {
                    Toggle("Open Reclaim at login", isOn: launchAtLogin)
                } else {
                    Toggle("Open Reclaim at login", isOn: .constant(false))
                        .disabled(true)
                }
                if let note = services.launchAtLoginNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Show reclaimable space in menu bar", selection: $settings.badgeMode) {
                    ForEach(BadgeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                LabeledContent("Keyboard shortcut to open Reclaim") {
                    ShortcutRecorder(shortcut: $settings.openPanelShortcut, problem: $shortcutProblem)
                }
                if let message = shortcutProblem ?? (settings.shortcutUnavailable ? "Another app is already using this shortcut. Record a different one." : nil) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                } else {
                    Text("Opens Reclaim from any app, even if its menu bar icon is hidden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Ask before emptying the Trash", isOn: $settings.askBeforeEmptying)
                Text("Emptying the Trash permanently erases its items. You can’t undo it. Erasing a single item always asks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                LabeledContent {
                    Button("Check Now", action: services.checkForUpdatesNow)
                } label: {
                    Label {
                        Text("Reclaim \(services.version)")
                    } icon: {
                        BrandBadge(size: 18)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

public struct CleaningSettingsPane: View {
    @Bindable var settings: AppSettings
    let services: SettingsServices

    public init(settings: AppSettings, services: SettingsServices) {
        self.settings = settings
        self.services = services
    }

    public var body: some View {
        Form {
            Section("Hidden macOS files") {
                Toggle("Also remove Spotlight indexes and FSEvents logs", isOn: $settings.includeSystemJunk)
                Text("Remove Hidden macOS Files removes .DS_Store files, ._ AppleDouble files, temporary items and Windows Thumbs.db caches from external drives. ._ files that hold Finder tags, comments or resource forks are always kept. Spotlight and FSEvents data is rebuilt automatically if the drive is used with a Mac again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Your Mac’s Trash") {
                LabeledContent("Full Disk Access") {
                    if services.fullDiskAccessGranted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color(nsColor: .systemGreen))
                    } else {
                        Button("Open Privacy & Security Settings…", action: services.openFullDiskAccessSettings)
                    }
                }
                Text("Reclaim needs Full Disk Access to measure and empty the Trash on your startup disk. Turn Reclaim on in the list, then reopen it when macOS asks. If Reclaim isn’t listed, click + and add it. External drives don’t need it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

public struct NotificationsSettingsPane: View {
    @Bindable var settings: AppSettings
    let services: SettingsServices

    public static let thresholdChoices = [5, 10, 15, 20, 25]

    public init(settings: AppSettings, services: SettingsServices) {
        self.settings = settings
        self.services = services
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Warn me when a drive is almost full", isOn: $settings.lowSpaceAlerts)
                Picker("Warn when available space drops below", selection: $settings.lowSpacePercent) {
                    ForEach(Self.thresholdChoices, id: \.self) { percent in
                        Text("\(percent)%").tag(percent)
                    }
                }
                .disabled(!settings.lowSpaceAlerts)
                Text("Reclaim sends one notification when a drive gets low, and another only if it recovers and gets low again, or a day later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
