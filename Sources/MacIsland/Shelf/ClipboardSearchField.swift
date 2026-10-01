import AppKit
import SwiftUI

/// The search field in the Shelf's header while the Clipboard shows: a capsule like the Reminders add field. Typing filters the cards
/// and marks the words that matched; Return pastes the first match; Esc clears it, then closes the island.
struct ClipboardSearchField: View {
    let viewModel: IslandViewModel

    @FocusState private var isFocused: Bool
    @Environment(\.isFloatingWindow) private var isFloating

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            TextField("Search", text: Bindable(viewModel).clipboardQuery)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primary)
                .focused($isFocused)
                .onSubmit { _ = viewModel.pasteFirstClipboardMatch() }
                .onExitCommand { if !viewModel.stepBack() { viewModel.closePinned() } }
                .accessibilityLabel("Search Clipboard")
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.hitTarget)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.fill, in: Capsule())
        .onChange(of: isFocused) { _, focused in if focused, !isFloating { viewModel.hold(.textFocus) } }
    }
}

/// Tells the view model whether ⌘ is down, for as long as the clipboard shows (a local monitor that goes with the view, so nothing
/// listens otherwise).
@MainActor
final class CommandKeyMonitor {
    private var monitor: Any?

    func start(_ onChange: @escaping @MainActor (Bool) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let held = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated { onChange(held) }
            return event
        }
    }

    func stop(_ onChange: @MainActor (Bool) -> Void) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onChange(false)
    }
}
