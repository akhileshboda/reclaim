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

    /// Global shortcuts need at least one of ⌘, ⌥ or ⌃, or they would swallow ordinary typing.
    public static func isAcceptable(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }
}
