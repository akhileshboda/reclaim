import AppKit
import ReclaimUI

/// Shows confirmations as a standard alert, styled like Finder's Empty Trash warning: the
/// destructive button is marked as such and Escape cancels.
@MainActor
final class AlertConfirmer: Confirming {
    func confirm(_ request: ConfirmationRequest) async -> Bool {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = request.title
        alert.informativeText = request.message
        let confirm = alert.addButton(withTitle: request.confirmTitle)
        confirm.hasDestructiveAction = request.isDestructive
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }
}
