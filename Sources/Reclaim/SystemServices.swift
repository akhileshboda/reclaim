import AppKit
import ServiceManagement
import UserNotifications
import ReclaimCore
import ReclaimUI

/// Low-space warnings as user notifications. Clicking one opens the panel on that drive; the
/// "Empty Trash…" action goes straight to the confirmation. Each drive has one notification at a
/// time (a repeat replaces the earlier one). In sandbox mode notifications are only logged, so
/// automated runs never put a permission prompt or banner on the user's screen.
@MainActor
final class Notifier: NSObject, LowSpaceNotifying, UNUserNotificationCenterDelegate {
    nonisolated static let categoryID = "lowSpace"
    nonisolated static let emptyTrashActionID = "emptyTrash"

    let mode: RuntimeMode
    /// Called with the drive ID, and whether the person chose Empty Trash….
    var onOpen: ((String, Bool) -> Void)?

    init(mode: RuntimeMode) {
        self.mode = mode
        super.init()
        guard mode == .live else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let empty = UNNotificationAction(identifier: Self.emptyTrashActionID, title: "Empty Trash…", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.categoryID, actions: [empty], intentIdentifiers: [])])
    }

    func notify(driveID: String, title: String, body: String) {
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
            content.categoryIdentifier = Self.categoryID
            content.userInfo = ["driveID": driveID]
            try? await center.add(UNNotificationRequest(identifier: "lowSpace-\(driveID)", content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let driveID = response.notification.request.content.userInfo["driveID"] as? String
        let wantsEmpty = response.actionIdentifier == Self.emptyTrashActionID
        await MainActor.run {
            if let driveID { onOpen?(driveID, wantsEmpty) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
