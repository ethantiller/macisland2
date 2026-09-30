import Carbon.HIToolbox

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
            guard let userData, let event else { return noErr }
            var pressed = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            // Every handler hears every hot key; only the one that registered it acts.
            guard pressed.signature == GlobalHotkey.signature, pressed.id == hotkey.id else { return noErr }
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkey.onPress?() } }
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
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
