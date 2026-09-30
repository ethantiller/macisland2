import ApplicationServices
import AppKit
import Observation

/// Swallows every key press for a short time so the keyboard can be wiped without typing anything.
/// The mouse keeps working, so the island's button (or the timeout) always brings the keyboard back.
/// Needs Accessibility access, which is asked for on first use.
@MainActor
@Observable
final class KeyboardCleaner {
    /// Long enough to wipe a keyboard, short enough that it can never strand anyone.
    static let lockDuration: Duration = .seconds(30)

    enum Outcome: Equatable {
        case locked
        case unlocked
        case needsAccess
        case failed
    }

    private(set) var isLocked = false

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var unlockTask: Task<Void, Never>?

    /// Key down, key up, modifier changes, and media keys (`NX_SYSDEFINED`).
    nonisolated static let swallowedTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, CGEventType(rawValue: 14)!]

    nonisolated static var hasAccess: Bool { AXIsProcessTrusted() }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggle() -> Outcome {
        if isLocked {
            unlock()
            return .unlocked
        }
        guard Self.hasAccess else {
            // Shows the system prompt once; after that it only opens the pane through the banner.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return .needsAccess
        }
        return lock() ? .locked : .failed
    }

    private func lock() -> Bool {
        let mask = Self.swallowedTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            // The system turns a tap off if it is slow; turn it back on, and keep swallowing.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let refcon {
                let cleaner = Unmanaged<KeyboardCleaner>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { if let tap = cleaner.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
            }
            return nil
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback, userInfo: context
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isLocked = true

        unlockTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lockDuration)
            guard !Task.isCancelled else { return }
            self?.unlock()
        }
        return true
    }

    func unlock() {
        unlockTask?.cancel()
        unlockTask = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isLocked = false
    }
}
