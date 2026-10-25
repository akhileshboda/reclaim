import AppKit
import ServiceManagement
import UserNotifications
import ReclaimCore
import ReclaimUI

/// Low-space warnings as user notifications. In sandbox mode they are only logged, so automated
/// runs never put a permission prompt or banner on the user's screen.
@MainActor
final class Notifier: LowSpaceNotifying {
    let mode: RuntimeMode

    init(mode: RuntimeMode) {
        self.mode = mode
    }

    func notify(title: String, body: String) {
        guard mode == .live else {
            print("[notification, not delivered in sandbox mode] \(title): \(body)")
            return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}

/// Open at login via SMAppService. Never touched in sandbox mode, because registering would
/// change the user's real login items.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}
