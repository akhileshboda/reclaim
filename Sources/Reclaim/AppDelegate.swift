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
    private var panelWindow: FloatingPanel?
    /// How tall the panel may be on the screen it's about to open on.
    private let panelLayout = PanelLayout()
    /// When the popover last closed. A click on the menu bar icon closes the transient popover on
    /// mouse-down, then the same click's mouse-up would open it again.
    private var popoverClosedAt: Date?
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
        observeScreens()
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

    /// True only when the icon is really on screen. macOS can report a status item as visible
    /// while it sits behind the camera notch or has been pushed off a crowded menu bar, and a
    /// popover anchored there opens partly off the screen.
    private var isStatusItemVisible: Bool {
        guard let item = statusItem, item.isVisible, let window = item.button?.window,
              let screen = window.screen, window.occlusionState.contains(.visible)
        else { return false }
        return ScreenGeometry.isFullyVisible(window.frame, on: screen)
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
        let host = NSHostingController(rootView: PanelView(model: model, actions: panelActions, layout: panelLayout))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    private func togglePanel() {
        if let closed = popoverClosedAt, Date().timeIntervalSince(closed) < 0.3, !popover.isShown {
            // The click that just closed the popover; don't reopen it.
            popoverClosedAt = nil
            return
        }
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
        if isStatusItemVisible, let button = statusItem?.button, let screen = button.window?.screen {
            // Room below the menu bar, less the popover's arrow and a margin.
            panelLayout.availableHeight = screen.visibleFrame.height - 28
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
        } else {
            showPanelWindow()
        }
    }

    /// The panel in a small floating window at the top right of the screen with the pointer,
    /// placed afresh every time so it can't reopen on a display that's gone.
    private func showPanelWindow() {
        let screen = ScreenGeometry.screenWithPointer() ?? NSScreen.main
        let panel = panelWindow ?? makePanelWindow()
        if let screen {
            // Leave room for the title bar and the inset from the screen edge.
            panelLayout.availableHeight = screen.visibleFrame.height - 60
            panel.anchor(toTopRightOf: screen.visibleFrame)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanelWindow() -> FloatingPanel {
        let host = NSHostingController(rootView: PanelView(model: model, actions: panelActions, layout: panelLayout))
        host.sizingOptions = [.preferredContentSize]
        let panel = FloatingPanel(contentViewController: host)
        panelWindow = panel
        return panel
    }

    /// Displays were added, removed or rescaled: keep the open panel on screen and within the
    /// new height.
    private func observeScreens() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let panel = self.panelWindow, panel.isVisible { self.showPanelWindow() }
                if self.popover.isShown, let screen = self.statusItem?.button?.window?.screen {
                    self.panelLayout.availableHeight = screen.visibleFrame.height - 28
                }
            }
        }
    }

    func popoverWillClose(_ notification: Notification) {
        popoverClosedAt = Date()
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
            // New drives are always scanned; the ones already shown keep their Trash figures, so
            // mounting a disk image doesn't wake every sleeping hard drive.
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.model.refresh(rescanning: []) }
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

    /// Reports a problem. Builds that know a feedback relay show a form that sends the message to
    /// the maintainer privately; others, and anyone who prefers it, open a GitHub issue with the
    /// Reclaim and macOS versions filled in.
    @objc private func reportBug() {
        popover.performClose(nil)
        guard let sender = FeedbackSender.configured(infoDictionary: Bundle.main.infoDictionary) else {
            openGitHubIssue()
            return
        }
        Task { await presentFeedbackForm(sender: sender) }
    }

    private func openGitHubIssue() {
        NSWorkspace.shared.open(BugReport.url(appVersion: AppInfo.version, macOSVersion: AppInfo.macOSVersion))
    }

    private func presentFeedbackForm(sender: FeedbackSender) async {
        NSApp.activate()
        let form = FeedbackForm()
        let alert = NSAlert()
        alert.messageText = "Report a bug or send feedback"
        alert.informativeText = "This goes privately to Reclaim’s developer, along with your Reclaim and macOS version numbers. Nothing else leaves your Mac, and nothing is sent until you press Send."
        alert.accessoryView = form.view
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Open GitHub Issue")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = form.messageView

        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard !form.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    alert.informativeText = "Please describe what happened first."
                    continue
                }
                let result = await sender.send(
                    message: form.message, replyTo: form.contact,
                    appVersion: AppInfo.version, macOSVersion: AppInfo.macOSVersion
                )
                result == .sent ? confirmFeedbackSent() : offerFeedbackFallback(message: form.message)
                return
            case .alertSecondButtonReturn:
                openGitHubIssue()
                return
            default:
                return
            }
        }
    }

    private func confirmFeedbackSent() {
        let alert = NSAlert()
        alert.messageText = "Thank you."
        alert.informativeText = "Your message was sent."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The message isn't lost when sending fails: it can be copied or taken to GitHub instead.
    private func offerFeedbackFallback(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t send your message."
        alert.informativeText = "Check your internet connection and try again, or copy your message and report it on GitHub instead."
        alert.addButton(withTitle: "Copy Message and Open GitHub")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
        openGitHubIssue()
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
