import AppKit
import Carbon.HIToolbox

/// Which global shortcut.
enum ShortcutSlot: String, CaseIterable {
    case open

    var title: String {
        switch self {
        case .open: "Open the Island"
        }
    }
}

/// A key and its modifiers, as Carbon's `RegisterEventHotKey` takes them. A global shortcut needs at least one of
/// Control, Option, or Command: a bare key, or Shift alone, would swallow typing everywhere.
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt32
    /// Carbon modifier flags (`controlKey`, `optionKey`, `cmdKey`, `shiftKey`).
    var modifiers: UInt32
    /// What the key is called, captured when it was recorded ("K", "Space", "F5").
    var label: String

    static let openDefault = KeyCombo(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), label: "Space")
    /// The old picker's other choice, kept so an existing choice carries over.
    static let controlOptionI = KeyCombo(
        keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | optionKey), label: "I")

    static let requiredModifiers = UInt32(controlKey | optionKey | cmdKey)

    var isValid: Bool { modifiers & Self.requiredModifiers != 0 && !label.isEmpty }

    /// "⌃⌥Space", in the order macOS writes them.
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { text += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { text += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0 { text += "\u{2318}" }
        return text + label
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    /// The combination for a key press, or nil when it can't be a global shortcut.
    static func from(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> KeyCombo? {
        let combo = KeyCombo(
            keyCode: UInt32(keyCode), modifiers: carbonModifiers(from: flags),
            label: keyName(keyCode: keyCode, characters: characters))
        return combo.isValid ? combo : nil
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "Forward Delete", kVK_Escape: "Esc", kVK_LeftArrow: "\u{2190}",
        kVK_RightArrow: "\u{2192}", kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}", kVK_Home: "Home",
        kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_F1: "F1", kVK_F2: "F2",
        kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9",
        kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(keyCode: UInt16, characters: String?) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        return characters?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
    }
}

/// A stored shortcut: nil means the person turned it off, which is different from never having chosen.
struct StoredShortcut: Codable, Equatable {
    var combo: KeyCombo?
}
