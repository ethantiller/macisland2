import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What one key press means to the recorder. Pure, so the rules are tested.
enum RecorderOutcome: Equatable {
    /// Esc alone: stop recording.
    case cancelled
    /// Delete alone: turn the shortcut off.
    case cleared
    /// A key without Control, Option, or Command.
    case needsModifier
    case combo(KeyCombo)

    static func of(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> RecorderOutcome {
        let modifiers = flags.intersection([.control, .option, .command, .shift])
        if modifiers.isEmpty {
            if Int(keyCode) == kVK_Escape { return .cancelled }
            if Int(keyCode) == kVK_Delete || Int(keyCode) == kVK_ForwardDelete { return .cleared }
        }
        guard let combo = KeyCombo.from(keyCode: keyCode, flags: modifiers, characters: characters) else {
            return .needsModifier
        }
        return .combo(combo)
    }
}

/// Listens for one key press while a recorder is armed. A local monitor, so it hears keys before anything else in
/// the window and swallows them (a recorded \u{2318}Q must not quit).
@MainActor
final class ShortcutCapture {
    private var monitor: Any?
    /// A recorder is listening for keys. The Settings tour leaves Return alone then.
    private(set) static var isActive = false

    func start(_ handler: @escaping (RecorderOutcome) -> Void) {
        stop()
        Self.isActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let outcome = RecorderOutcome.of(
                keyCode: event.keyCode, flags: event.modifierFlags, characters: event.charactersIgnoringModifiers)
            MainActor.assumeIsolated { handler(outcome) }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Self.isActive = false
    }

    isolated deinit { stop() }
}

/// A shortcut field: click it, press the keys. It refuses a key another app already owns, says so, and keeps the old
/// shortcut.
struct ShortcutRecorder: View {
    let settings: AppSettings
    let slot: ShortcutSlot

    @State private var isRecording = false
    @State private var message: String?
    @State private var capture = ShortcutCapture()

    var body: some View {
        LabeledContent(slot.title) {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Button(isRecording ? "Type a Shortcut\u{2026}" : (settings.shortcut(slot)?.display ?? "Off")) {
                        isRecording ? stop() : begin()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(slot.title) shortcut")
                    .accessibilityValue(settings.shortcut(slot)?.display ?? "Off")
                    if settings.shortcut(slot) != nil, !isRecording {
                        Button {
                            settings.setShortcut(slot, nil)
                            message = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Turn Off \(slot.title) Shortcut")
                    }
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onDisappear { stop() }
    }

    private func begin() {
        message = nil
        isRecording = true
        capture.start { outcome in
            switch outcome {
            case .cancelled: stop()
            case .cleared:
                settings.setShortcut(slot, nil)
                stop()
            case .needsModifier:
                message = "Include \u{2303}, \u{2325}, or \u{2318}."
            case .combo(let combo):
                if let other = settings.slot(holding: combo, besides: slot) {
                    message = "Already used for \(other.title)."
                } else if settings.setShortcut(slot, combo) {
                    message = nil
                    stop()
                } else {
                    message = "In use by another app. Try a different one."
                }
            }
        }
    }

    private func stop() {
        capture.stop()
        isRecording = false
    }
}
