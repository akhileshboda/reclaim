import AppKit
import SwiftUI
import ReclaimCore
import ReclaimUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let options = LaunchOptions.parse()
    private lazy var settings = AppSettings(store: options.mode == .sandbox ? InMemorySettingsStore() : UserDefaults.standard)
    private lazy var model = AppModel(mode: options.mode, settings: settings, confirmer: AlertConfirmer())
    private lazy var notifier = Notifier(mode: options.mode)
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        persistsState: options.mode == .live,
        services: { [unowned self] in settingsServices() }
    )
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    /// Used when the menu bar icon isn't visible (hidden by the notch or a crowded menu bar).
    private var panelWindow: NSWindow?
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
        // Opening a Full Disk Access folder is what makes macOS list Reclaim in that pane, with its
        // switch off, so the person turns it on instead of adding the app by hand.
        if options.mode == .live { Task.detached(priority: .userInitiated) { _ = FullDiskAccessProbe().status() } }
        setUpStatusItem()
        setUpPopover()
        observeVolumes()
        observeBadge()
        observeShortcut()
        observeTrashFolders()
        HotKey.shared.onPress = { [weak self] in self?.togglePanel() }
        notifier.onOpen = { [weak self] driveID, wantsEmpty in
            guard let self else { return }
            showPanel()
            model.showTrashPeek(driveID: driveID)
            if wantsEmpty { Task { await self.model.emptyTrash(driveID: driveID) } }
        }

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
        if options.openPanel { showPanel() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Returning from System Settings may have granted Full Disk Access: rescan only the
        // Trash folders that were unreadable, not every drive.
        let denied = Set(model.drives.filter { $0.trash.access == .denied }.map(\.id))
        if !denied.isEmpty { Task { await model.refresh(rescanning: denied) } }
    }

    /// Opening Reclaim again (Finder, Spotlight, Launchpad) shows the panel, so the app stays
    /// reachable even when its menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.image = Brand.menuBarImage()
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Reclaim"
        statusItem = item
    }

    private var isStatusItemVisible: Bool {
        guard let item = statusItem, item.isVisible, let window = item.button?.window else { return false }
        return window.occlusionState.contains(.visible) && window.screen != nil
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
            // A plain title (not an attributed one without a colour, which AppKit draws black)
            // lets the menu bar apply its own colour for light, dark and highlighted states.
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
            button.title = " " + text
            button.setAccessibilityLabel("Reclaim, \(text) can be reclaimed")
        } else {
            button.title = ""
            button.setAccessibilityLabel("Reclaim")
        }
    }

    private func observeShortcut() {
        let registered = withObservationTracking {
            HotKey.shared.register(settings.openPanelShortcut)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeShortcut() }
        }
        settings.shortcutUnavailable = !registered
        if !registered, let shortcut = settings.openPanelShortcut {
            model.notice = Notice(kind: .warning, text: "Another app is using \(shortcut.displayString). Choose a different shortcut in Settings › General.")
        }
    }

    private func observeTrashFolders() {
        withObservationTracking {
            trashWatcher.watch(model.watchableTrashPaths)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTrashFolders() }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    /// The same commands, in the same order, as the panel's More menu.
    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "About Reclaim", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Report a Bug…", action: #selector(reportBug), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Reclaim", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: Panel

    private var panelActions: PanelActions {
        PanelActions(
            openSettings: { [weak self] in self?.openSettings() },
            openFullDiskAccessSettings: { [weak self] in self?.openFullDiskAccessSettings() },
            restart: { [weak self] in self?.restart() },
            checkForUpdates: { [weak self] in self?.checkForUpdatesFromMenu() },
            reportBug: { [weak self] in self?.reportBug() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
    }

    private func setUpPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, actions: panelActions))
    }

    private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let panelWindow, panelWindow.isVisible {
            panelWindow.close()
        } else {
            showPanel()
        }
    }

    /// Shows the panel under the menu bar icon, or in a small window when the icon isn't visible.
    func showPanel() {
        // Watched Trash folders are already current; only refresh capacities, plus any Trash the
        // watcher can't see. Opening the panel shouldn't wake sleeping hard drives.
        Task { await model.refresh(rescanning: model.unwatchedDriveIDs) }
        NSApp.activate()
        if isStatusItemVisible, let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
        } else {
            showPanelWindow()
        }
    }

    private func showPanelWindow() {
        if panelWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PanelView(model: model, actions: panelActions)))
            window.title = "Reclaim"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            panelWindow = window
        }
        panelWindow?.makeKeyAndOrderFront(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        // Notices stay until read; once the panel closes they've had their chance.
        model.notice = nil
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

    /// Opens Privacy & Security › Full Disk Access. Reclaim is refused once first, off the main
    /// thread and before the pane opens, so macOS has listed it by the time the person looks.
    private func openFullDiskAccessSettings() {
        popover.performClose(nil)
        model.awaitingFullDiskAccess = true
        Task.detached(priority: .userInitiated) {
            _ = FullDiskAccessProbe().status()
            await MainActor.run { _ = NSWorkspace.shared.open(FullDiskAccessProbe.settingsURL) }
        }
    }

    /// Starts a fresh copy and quits this one: macOS only applies a new Full Disk Access grant
    /// to a process that launches after it.
    private func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
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
        let status = await checker.check()
        if case .available(let release) = status { model.availableUpdate = release }
        guard userInitiated else { return }

        NSApp.activate()
        let alert = NSAlert()
        switch status {
        case .available(let release):
            alert.messageText = "Reclaim \(release.version?.description ?? release.tagName) is available."
            alert.informativeText = "You have version \(AppInfo.version). The download page lists what’s new."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
        case .upToDate:
            alert.messageText = "Reclaim is up to date."
            alert.informativeText = "You’re running version \(AppInfo.version)."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .unknown:
            alert.messageText = "Couldn’t check for updates."
            alert.informativeText = "Reclaim couldn’t reach GitHub. Try again later, or look at the releases page."
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Releases Page")
            if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(checker.releasesPage) }
        }
    }

    // MARK: Other

    @objc private func showAbout() {
        popover.performClose(nil)
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(
                string: "\(Brand.tagline)\n\nOpen source under the MIT License.\nNot affiliated with MacPaw or CleanMyDrive.",
                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    /// Opens a GitHub bug report in the browser with the Reclaim and macOS versions filled in.
    @objc private func reportBug() {
        popover.performClose(nil)
        NSWorkspace.shared.open(BugReport.url(appVersion: AppInfo.version, macOSVersion: AppInfo.macOSVersion))
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

/// Command-line switches. `--sandbox` limits the app to RTEST-* test disks; `--capture <dir>`
/// renders the panel and Settings to PNGs and exits; `--open-panel` opens the panel at launch.
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
