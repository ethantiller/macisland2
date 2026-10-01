import AppKit
import Intents
import Observation

/// Whether a Focus (Do Not Disturb, Work, Sleep...) is on, and a way to switch it.
///
/// Reading uses `INFocusStatusCenter`, which reports only "a Focus is on" and asks the person once.
/// macOS has no public way to *change* a Focus, so switching runs the person's own Shortcuts
/// named `Focus On` and `Focus Off` (each a single "Set Focus" action).
@MainActor
@Observable
final class FocusMode {
    static let onShortcut = "Focus On"
    static let offShortcut = "Focus Off"

    private(set) var isFocused = false
    /// The person said no in the system prompt.
    private(set) var isDenied = false

    @ObservationIgnored private var isStarted = false

    /// Whether the person has already allowed it, read without asking. The launch starts Focus only when this is true.
    static var isAuthorized: Bool { INFocusStatusCenter.default.authorizationStatus == .authorized }

    /// Starts reading Focus. Asks for permission the first time; call only once it's needed.
    ///
    /// There's no change notification for Focus, and nothing polls it in the background (that was a standing timer
    /// while nothing is live): a decision that needs it reads it then (`readNow`), and the Focus button reads it while
    /// it is shown (`watch`).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Whether a Focus is on right now, read fresh once started.
    func readNow() -> Bool {
        if isStarted { refresh() }
        return isFocused
    }

    /// Reads Focus every few seconds until cancelled, once started (the button itself may be what starts it). Run from
    /// the `.task` of a view that shows it.
    func watch() async {
        while !Task.isCancelled {
            if isStarted { refresh() }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refresh() {
        let center = INFocusStatusCenter.default
        isDenied = center.authorizationStatus == .denied
        update(center.focusStatus.isFocused ?? false)
    }

    /// Also how tests set the state.
    func update(_ focused: Bool) {
        if focused != isFocused { isFocused = focused }
    }

    /// Runs the person's Shortcut. `completion(false)` means it isn't there yet.
    func toggle(completion: @escaping (Bool) -> Void) {
        let name = isFocused ? Self.offShortcut : Self.onShortcut
        Task.detached {
            let found = Self.runShortcut(named: name)
            await MainActor.run { completion(found) }
        }
    }

    nonisolated private static func runShortcut(named name: String) -> Bool {
        guard let listing = run(["list"]), listing.split(separator: "\n").contains(where: { $0 == name }) else {
            return false
        }
        _ = run(["run", name])
        return true
    }

    nonisolated private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    static func openShortcuts() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
    }
}
