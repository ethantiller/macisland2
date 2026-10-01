import ApplicationServices
import SwiftUI

/// One button's worth of tool: what it's called, how it looks, and what it does.
struct ToolItem: Identifiable {
    let id: ToolID
    let title: String
    /// The full name where there is room for it (VoiceOver); defaults to `title`.
    var label: String?
    let systemImage: String
    var isOn = false
    var isAvailable = true
    /// Keeps `isOn` current while the button is on screen, for a state with no change notification (Focus).
    var watch: (() async -> Void)?
    let action: () -> Void
}

/// What each tool is and does. Shared by the Tools tab, Home, and the idle peek.
@MainActor
struct ToolCatalog {
    let viewModel: IslandViewModel

    func item(for id: ToolID) -> ToolItem {
        switch id {
        case .keepAwake:
            ToolItem(id: id, title: "Keep Awake", systemImage: "cup.and.saucer.fill", isOn: viewModel.keepAwake.isOn) {
                viewModel.keepAwake.toggle()
            }
        case .ringLight:
            ToolItem(id: id, title: "Ring Light", systemImage: "lightbulb.fill", isOn: viewModel.ringLight.isOn) {
                withAnimation(Theme.Motion.resize) { viewModel.ringLight.toggle() }
            }
        case .muteMic:
            ToolItem(
                id: id,
                title: "Mute Mic",
                systemImage: viewModel.micMute.isMuted ? "mic.slash.fill" : "mic.fill",
                isOn: viewModel.micMute.isMuted,
                isAvailable: viewModel.micMute.isAvailable
            ) { viewModel.micMute.toggle() }
        case .pickColor:
            ToolItem(id: id, title: "Pick Color", systemImage: "eyedropper") {
                SystemActions.pickColor { color in
                    let hex = SystemActions.hexString(for: color)
                    SystemActions.copyToClipboard(hex)
                    viewModel.flash(
                        IslandAlert(
                            systemImage: "circle.fill", tint: Color(nsColor: color), text: hex, tintsText: false
                        ), respectingFocus: false)
                }
            }
        case .screenshot:
            ToolItem(id: id, title: "Screenshot", systemImage: "camera.viewfinder") {
                SystemActions.captureScreenshotToClipboard { copied in
                    guard copied else { return }
                    viewModel.flash(
                        IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
                        respectingFocus: false
                    )
                }
            }
        case .focus:
            ToolItem(
                id: id, title: "Focus", systemImage: "moon.fill", isOn: viewModel.focus.isFocused,
                watch: { [focus = viewModel.focus] in await focus.watch() }
            ) {
                toggleFocus()
            }
        case .cleanKeyboard:
            ToolItem(id: id, title: "Clean Keys", systemImage: "keyboard", isOn: viewModel.keyboardCleaner.isLocked) {
                toggleKeyboardLock()
            }
        case .mirror:
            ToolItem(id: id, title: "Mirror", systemImage: "person.crop.rectangle", isOn: viewModel.mirror.isOn) {
                viewModel.toggleMirror()
            }
        case .recordScreen:
            ToolItem(
                id: id, title: "Record", label: "Record Screen", systemImage: "record.circle",
                isOn: viewModel.screenRecorder.isRecording
            ) { viewModel.toggleScreenRecording() }
        default:
            shortcutItem(for: id)
        }
    }

    /// A tool the person made from a Shortcut: pressing it runs the Shortcut. It is dimmed, with nothing to press, when the Shortcut
    /// is no longer in Shortcuts (deleted or renamed); right-click it to edit or remove the tool.
    private func shortcutItem(for id: ToolID) -> ToolItem {
        guard let tool = viewModel.settings.shortcutTool(for: id) else {
            return ToolItem(id: id, title: "Missing", systemImage: "questionmark.square.dashed", isAvailable: false) {}
        }
        let installed = viewModel.installedShortcuts
        return ToolItem(
            id: id, title: tool.title, label: "Run \(tool.shortcut)", systemImage: tool.systemImage,
            isOn: viewModel.runningShortcutTools.contains(tool.id),
            isAvailable: installed?.contains(tool.shortcut) ?? true
        ) { viewModel.runShortcutTool(tool) }
    }

    /// Locks every key for 30 seconds, after asking for Accessibility access the first time.
    private func toggleKeyboardLock() {
        let cleaner = viewModel.keyboardCleaner
        switch cleaner.toggle() {
        case .locked:
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "keyboard",
                    tint: Theme.Tint.neutral,
                    title: "Keyboard Locked",
                    detail: "Unlocks in 30 seconds",
                    actions: [.init(title: "Unlock") { cleaner.unlock() }]
                ),
                for: .seconds(30),
                respectingFocus: false
            )
        case .needsAccess:
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "hand.raised.fill",
                    tint: Theme.Tint.attention,
                    title: "Accessibility Access Needed",
                    detail: "Allow it to lock the keyboard",
                    actions: [.init(title: "Open Settings") { KeyboardCleaner.openAccessibilitySettings() }]
                ),
                for: .seconds(8),
                respectingFocus: false
            )
        case .failed:
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "keyboard",
                    tint: Theme.Tint.attention,
                    title: "Couldn\u{2019}t Lock the Keyboard",
                    detail: "Check Accessibility access"
                ),
                for: .seconds(6),
                respectingFocus: false
            )
        case .unlocked:
            break
        }
    }

    /// Focus can only be switched through the person's own Shortcuts; say how to set them up if missing.
    private func toggleFocus() {
        viewModel.focus.start()
        viewModel.focus.toggle { found in
            guard !found else { return }
            viewModel.showBanner(
                IslandBanner(
                    systemImage: "moon.fill",
                    tint: Theme.Tint.neutral,
                    title: "Focus Needs Shortcuts",
                    detail: "\(FocusMode.onShortcut) and \(FocusMode.offShortcut)",
                    actions: [.init(title: "Open Shortcuts") { FocusMode.openShortcuts() }]
                ),
                for: .seconds(8),
                respectingFocus: false
            )
        }
    }
}
