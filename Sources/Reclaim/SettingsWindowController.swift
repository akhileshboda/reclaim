import AppKit
import SwiftUI
import ReclaimUI

/// A standard macOS Settings window: toolbar tabs, title follows the selected pane, not resizable.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, services: @escaping () -> SettingsServices) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        tabs.addTabViewItem(Self.item("General", symbol: "gearshape", GeneralPaneHost(settings: settings, services: services)))
        tabs.addTabViewItem(Self.item("Cleaning", symbol: "sparkles", CleaningPaneHost(settings: settings, services: services)))
        tabs.addTabViewItem(Self.item("Notifications", symbol: "bell.badge", NotificationsPaneHost(settings: settings, services: services)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    private static func item(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }

    func show() {
        NSApp.activate()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
