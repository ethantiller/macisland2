import Carbon.HIToolbox
import os

/// Where the shortcuts log: `log stream --predicate 'subsystem == "com.ethantiller.MacIsland"'`. Cheap, and what a hand test of a
/// shortcut that did nothing needs.
enum HotkeyLog {
    static let logger = Logger(subsystem: "com.ethantiller.MacIsland", category: "hotkey")
    static let accessLogger = Logger(subsystem: "com.ethantiller.MacIsland", category: "access")
}

/// A system-wide shortcut. Carbon's `RegisterEventHotKey` needs no Accessibility permission. Each instance has its
/// own id, so several can live side by side and each hears only its own key.
@MainActor
final class GlobalHotkey {
    /// Control-Option-Space: free in macOS by default.
    nonisolated static let defaultKeyCode = UInt32(kVK_Space)
    nonisolated static let defaultModifiers = UInt32(controlKey | optionKey)
    nonisolated private static let signature = OSType(0x4D_49_53_4C)  // 'MISL'

    var onPress: (() -> Void)?

    private let id: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(id: UInt32 = 1) {
        self.id = id
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            // Every handler hears every hot key, newest first; only the one that registered it acts. The others must say they did not
            // handle it (`noErr` would end the dispatch, and the key would never reach its own handler: the open shortcut never fired
            // while the Shelf's handler, installed after it, answered first).
            guard pressed.signature == GlobalHotkey.signature, pressed.id == hotkey.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    HotkeyLog.logger.info("press id=\(hotkey.id) hasHandler=\(hotkey.onPress != nil)")
                    hotkey.onPress?()
                }
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &spec,
            Unmanaged.passUnretained(self).toOpaque(), &handler
        )
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Returns `false` if another app already owns the combination.
    @discardableResult
    func register(keyCode: UInt32 = defaultKeyCode, modifiers: UInt32 = defaultModifiers) -> Bool {
        unregister()
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
        HotkeyLog.logger.info("register id=\(self.id) key=\(keyCode) modifiers=\(modifiers) status=\(status)")
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    /// Whether the key is registered right now.
    var isRegistered: Bool { hotKey != nil }
}
