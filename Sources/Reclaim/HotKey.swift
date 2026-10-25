import Carbon.HIToolbox
import ReclaimUI

/// A system-wide keyboard shortcut via Carbon's RegisterEventHotKey, which (unlike event taps)
/// needs no Accessibility permission.
@MainActor
final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers `shortcut`, replacing any previous one. Returns false if macOS refused it
    /// (usually because another app already owns that combination).
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        unregister()
        guard let shortcut else { return true }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: 0x52434C4D /* 'RCLM' */, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
