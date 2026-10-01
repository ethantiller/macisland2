import ApplicationServices
import CoreGraphics

/// Sends ⌘V to the app that has the keyboard. Behind a protocol, so tests never press a key.
@MainActor
protocol Pasting {
    /// Whether pasting is possible: it needs Accessibility, which is one of the ten permissions and is never asked for here.
    var canPaste: Bool { get }
    /// Presses ⌘V. False when it could not.
    func paste() -> Bool
}

@MainActor
struct LivePaster: Pasting {
    var canPaste: Bool { AXIsProcessTrusted() }

    func paste() -> Bool {
        guard canPaste, let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

/// The keys that paste from the history while it shows: ⌘1 to ⌘9 paste the nth copy shown, Return the first.
enum ClipboardShortcut {
    /// The digit a key code is on the number row (not the keypad), or nil.
    static func digit(forKeyCode keyCode: UInt16) -> Int? {
        [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][Int(keyCode)]
    }

    /// The key cap on the nth card (counting from 0): only the first nine, and only while ⌘ is held.
    static func keyCap(forIndex index: Int, commandHeld: Bool) -> String? {
        commandHeld && (0..<9).contains(index) ? "\u{2318}\(index + 1)" : nil
    }
}
