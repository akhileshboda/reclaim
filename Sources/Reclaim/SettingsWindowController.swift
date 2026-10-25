import AppKit
import SwiftUI
import ReclaimUI

/// A standard macOS Settings window: toolbar panes, title follows the selected pane, not
/// resizable, reopens on the last pane at its last position.
@MainActor
final class SettingsWindowController: NSWindowController {
    /// `persistsState` is false in sandbox mode, so test runs never write window state into the
    /// user's preferences.
    convenience init(settings: AppSettings, persistsState: Bool, services: @escaping () -> SettingsServices) {
        let tabs = SettingsTabViewController(persistsState: persistsState)
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        tabs.addTabViewItem(Self.item("General", symbol: "gearshape", GeneralPaneHost(settings: settings, services: services)))
        tabs.addTabViewItem(Self.item("Cleaning", symbol: "sparkles", CleaningPaneHost(settings: settings, services: services)))
        tabs.addTabViewItem(Self.item("Notifications", symbol: "bell", NotificationsPaneHost(settings: settings, services: services)))
        tabs.restoreSelectedPane()

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
        if persistsState {
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            window.setFrameAutosaveName(Self.frameName)
        } else {
            window.center()
        }
        self.init(window: window)
    }

    private static let frameName = "ReclaimSettings"

    private static func item(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsTabViewController: NSTabViewController {
    private static let paneKey = "settingsSelectedPane"
    private let persistsState: Bool

    init(persistsState: Bool) {
        self.persistsState = persistsState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func restoreSelectedPane() {
        guard persistsState else { return }
        let saved = UserDefaults.standard.integer(forKey: Self.paneKey)
        if tabViewItems.indices.contains(saved) { selectedTabViewItemIndex = saved }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? "Settings"
        if persistsState { UserDefaults.standard.set(selectedTabViewItemIndex, forKey: Self.paneKey) }
    }
}

// The hosts re-read the services each time SwiftUI re-renders, so the Full Disk Access and
// launch-at-login state stay current while the window is open.
private struct GeneralPaneHost: View {
    let settings: AppSettings
    let services: () -> SettingsServices
    var body: some View { GeneralSettingsPane(settings: settings, services: services()) }
}

private struct CleaningPaneHost: View {
    let settings: AppSettings
    let services: () -> SettingsServices
    var body: some View { CleaningSettingsPane(settings: settings, services: services()) }
}

private struct NotificationsPaneHost: View {
    let settings: AppSettings
    let services: () -> SettingsServices
    var body: some View { NotificationsSettingsPane(settings: settings, services: services()) }
}
