import AppKit
import SwiftUI
import ReclaimCore
import ReclaimUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let options = LaunchOptions.parse()
    private lazy var settings = AppSettings(store: options.mode == .sandbox ? InMemorySettingsStore() : UserDefaults.standard)
    private lazy var model = AppModel(mode: options.mode, settings: settings, confirmer: AlertConfirmer())
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = options.captureDirectory {
            Task { await CaptureRunner(model: model, directory: directory).run() }
            return
        }
        setUpStatusItem()
        setUpPopover()
        observeVolumes()
        observeBadge()
        Task { await model.refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
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

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
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
            checkForUpdates: {},
            showAbout: { [weak self] in self?.showAbout() },
            quit: { [weak self] in self?.quit() }
        )
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, actions: actions))
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        Task { await model.refresh() }
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

    // MARK: Actions

    @objc func openSettings() {
        popover.performClose(nil)
    }

    private func openFullDiskAccessSettings() {
        popover.performClose(nil)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

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
/// renders the panel to PNGs and exits; `--open-panel` opens the popover at launch.
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
