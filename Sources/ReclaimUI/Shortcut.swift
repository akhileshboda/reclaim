import AppKit

/// A global keyboard shortcut, stored as the physical key plus modifiers.
public struct Shortcut: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt
    /// What the key shows, e.g. "R".
    public var key: String

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
        self.key = key.uppercased()
    }

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// ⌃⌥⌘R. Unlikely to collide with app shortcuts, which rarely use all three modifiers.
    public static let defaultOpenPanel = Shortcut(keyCode: 15, modifiers: [.control, .option, .command], key: "R")

    public var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Symbols in the order macOS menus use: ⌃ ⌥ ⇧ ⌘.
    public var displayString: String {
        let flags = modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + key
    }

    /// Spoken form for VoiceOver, e.g. "Control Option Command R".
    public var accessibilityLabel: String {
        let flags = modifierFlags
        var words: [String] = []
        if flags.contains(.control) { words.append("Control") }
        if flags.contains(.option) { words.append("Option") }
        if flags.contains(.shift) { words.append("Shift") }
        if flags.contains(.command) { words.append("Command") }
        return (words + [key]).joined(separator: " ")
    }

    /// Carbon modifier mask for RegisterEventHotKey (cmdKey, shiftKey, optionKey, controlKey).
    public var carbonModifiers: UInt32 {
        let flags = modifierFlags
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= 0x0100 }
        if flags.contains(.shift) { mask |= 0x0200 }
        if flags.contains(.option) { mask |= 0x0800 }
        if flags.contains(.control) { mask |= 0x1000 }
        return mask
    }

    /// System-wide shortcuts with two modifiers that people rely on.
    static let reservedShortcuts: [String: String] = [
        "⌃⌘Q": "Lock Screen", "⌃⌘F": "Enter Full Screen", "⌃⌘ ": "Emoji & Symbols",
        "⌥⌘D": "Show or Hide the Dock", "⌥⌘H": "Hide Others", "⌥⌘M": "Minimize All",
        "⌥⌘W": "Close All", "⌥⌘I": "Show Inspector", "⌥⌘T": "Show or Hide the Toolbar",
        "⌥⌘S": "Save All", "⌥⌘V": "Move Item Here", "⌥⌘L": "Downloads folder",
    ]

    /// Why a combination can't be a global shortcut, or nil if it can. A global shortcut works in
    /// every app, so it must not take over standard shortcuts like ⌘C or ⌘Q, or a typed character
    /// like ⌥E: it needs at least two of ⌃, ⌥ and ⌘.
    public static func problem(modifiers: NSEvent.ModifierFlags, key: String) -> String? {
        let strong = modifiers.intersection([.control, .option, .command])
        let count = [NSEvent.ModifierFlags.control, .option, .command].filter { strong.contains($0) }.count
        let candidate = Shortcut(keyCode: 0, modifiers: modifiers, key: key)
        guard count >= 2 else {
            return "\(candidate.displayString) would take over a shortcut or character other apps use. Use at least two of Control, Option and Command."
        }
        if let name = reservedShortcuts[candidate.displayString] {
            return "\(candidate.displayString) is the system shortcut for \(name). Choose a different one."
        }
        return nil
    }
}
