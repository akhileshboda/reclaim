import AppKit
import SwiftUI
import ReclaimCore
import ReclaimUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options = LaunchOptions.parse()
    private lazy var settings = AppSettings(store: options.mode == .sandbox ? InMemorySettingsStore() : UserDefaults.standard)
    private lazy var model = AppModel(mode: options.mode, settings: settings, confirmer: AlertConfirmer())
    private lazy var notifier = Notifier(mode: options.mode)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, services: { [unowned self] in settingsServices() })
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var timers: [Timer] = []
    private lazy var trashWatcher = DirectoryWatcher { [weak self] paths in
        guard let self else { return }
        let ids = model.driveIDs(containing: paths)
        if !ids.isEmpty { Task { await self.model.refresh(rescanning: ids) } }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.lowSpaceNotifier = notifier
        if let directory = options.captureDirectory {
            Task { await CaptureRunner(model: model, services: settingsServices(), directory: directory).run() }
            return
        }
        setUpStatusItem()
        setUpPopover()
        observeVolumes()
        observeBadge()
        observeShortcut()
        observeTrashFolders()
        HotKey.shared.onPress = { [weak self] in self?.togglePopover() }

        Task { await model.refresh() }
        // Capacities only: Trash folders are rescanned when FSEvents reports a change, so idle
        // external hard drives are left asleep.
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh(rescanning: []) }
        })
        if options.mode == .live {
            Task { await checkForUpdates(userInitiated: false) }
            timers.append(Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.checkForUpdates(userInitiated: false) }
            })
        }
        if options.openPanel { showPopover() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Returning from System Settings may have granted Full Disk Access.
        Task { await model.refresh() }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        let image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Reclaim")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Reclaim"
        statusItem = item
    }

    private func observeBadge() {
        withObservationTracking {
            updateBadge(model.badgeText)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }

    private func updateBadge(_ text: String?) {
        guard let button = statusItem?.button else { return }
        if let text {
            button.attributedTitle = NSAttributedString(string: " " + text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular),
            ])
            button.setAccessibilityLabel("Reclaim, \(text) can be reclaimed")
        } else {
            button.title = ""
            button.setAccessibilityLabel("Reclaim")
        }
    }

    private func observeTrashFolders() {
        withObservationTracking {
            trashWatcher.watch(model.watchableTrashPaths)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTrashFolders() }
        }
    }

    private func observeShortcut() {
        let registered = withObservationTracking {
            HotKey.shared.register(settings.openPanelShortcut)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcut() }
        }
        if !registered, let shortcut = settings.openPanelShortcut {
            model.notice = Notice(kind: .warning, text: "Another app is using \(shortcut.displayString). Choose a different shortcut in Settings.")
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Reclaim", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: Popover

    private func setUpPopover() {
        popover.behavior = .transient
        popover.animates = true
        let actions = PanelActions(
            openSettings: { [weak self] in self?.openSettings() },
            openFullDiskAccessSettings: { [weak self] in self?.openFullDiskAccessSettings() },
            checkForUpdates: { [weak self] in self?.checkForUpdatesFromMenu() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, actions: actions))
    }

    private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        Task { await model.refresh() }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Volumes

    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.model.refresh() }
            }
        }
    }

    // MARK: Settings

    private func settingsServices() -> SettingsServices {
        let bootReadable = model.drives.first { $0.drive.isBoot }?.trash.access == .readable
        let launchBinding: Binding<Bool>? = options.mode == .sandbox ? nil : Binding(
            get: { LaunchAtLogin.isEnabled },
            set: { enabled in try? LaunchAtLogin.set(enabled) }
        )
        return SettingsServices(
            launchAtLogin: launchBinding,
            launchAtLoginNote: options.mode == .sandbox ? "Not available in sandbox mode, so test runs never change your login items." : nil,
            fullDiskAccessGranted: bootReadable,
            openFullDiskAccessSettings: { [weak self] in self?.openFullDiskAccessSettings() },
            checkForUpdatesNow: { [weak self] in self?.checkForUpdatesFromMenu() },
            version: AppInfo.version
        )
    }

    @objc func openSettings() {
        popover.performClose(nil)
        settingsWindow.show()
    }

    private func openFullDiskAccessSettings() {
        popover.performClose(nil)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Updates

    @objc private func checkForUpdatesFromMenu() {
        popover.performClose(nil)
        Task { await checkForUpdates(userInitiated: true) }
    }

    private func checkForUpdates(userInitiated: Bool) async {
        guard userInitiated || settings.checkForUpdates else { return }
        let checker = UpdateChecker(currentVersion: SemanticVersion(AppInfo.version) ?? SemanticVersion("0.0.0")!)
        let release = await checker.newerRelease()
        model.availableUpdate = release
        guard userInitiated else { return }

        NSApp.activate()
        let alert = NSAlert()
        if let release {
            alert.messageText = "Reclaim \(release.version?.description ?? release.tagName) is available"
            alert.informativeText = "You have version \(AppInfo.version). The download page has what’s new."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
        } else {
            alert.messageText = "No update found"
            alert.informativeText = "You’re running Reclaim \(AppInfo.version). Releases are listed on GitHub."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(checker.releasesPage) }
        }
    }

    // MARK: Other

    private func showAbout() {
        popover.performClose(nil)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Open source under the MIT License.\nNot affiliated with MacPaw or CleanMyDrive."),
        ])
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

/// Command-line switches. `--sandbox` limits the app to RTEST-* test disks; `--capture <dir>`
/// renders the panel and Settings to PNGs and exits; `--open-panel` opens the popover at launch.
struct LaunchOptions {
    let mode: RuntimeMode
    let captureDirectory: URL?
    let openPanel: Bool

    static func parse(_ arguments: [String] = CommandLine.arguments) -> LaunchOptions {
        var capture: URL?
        if let index = arguments.firstIndex(of: "--capture"), arguments.indices.contains(index + 1) {
            capture = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        return LaunchOptions(mode: RuntimeMode.detect(arguments: arguments), captureDirectory: capture, openPanel: arguments.contains("--open-panel"))
    }
}
