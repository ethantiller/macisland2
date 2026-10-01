import Carbon.HIToolbox
import Testing

@testable import MacIsland

/// Every `GlobalHotkey` installs its own Carbon handler, and the newest hears a key first. A handler that answered `noErr` for a key
/// that wasn't its own ended the dispatch, so the open shortcut never fired once the Shelf's was installed after it.
@MainActor
struct HotkeyDispatchTests {
    private func send(id: UInt32) {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event)
        guard let event else { return }
        var hotKeyID = EventHotKeyID(signature: OSType(0x4D_49_53_4C), id: id)
        SetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
    }

    @Test func eachKeyReachesItsOwnHandlerWhateverWasInstalledLater() async throws {
        let open = GlobalHotkey(id: 101)
        let shelf = GlobalHotkey(id: 102)  // installed after: hears every key first
        var opened = 0
        var shelved = 0
        open.onPress = { opened += 1 }
        shelf.onPress = { shelved += 1 }
        send(id: 101)
        send(id: 102)
        try await Task.sleep(for: .milliseconds(100))
        #expect(opened == 1 && shelved == 1)
    }
}
