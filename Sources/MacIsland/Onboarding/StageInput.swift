import SwiftUI
import UniformTypeIdentifiers

/// Lets the first-run guide's stage answer the way the island does: to the pointer resting on it, a click, two-finger swipes, and a
/// file dragged over it. The stage draws the real `IslandView` over sample features and stays look-only, because its own controls
/// would act on this Mac (the microphone, the audio output, the keyboard). This layer passes on only what the island itself answers
/// to, by calling the same view-model methods the real island's tracker does: `setHovering`, `open`, `perform(_:)`, and
/// `setFileDragActive`. The keys (Esc, the arrows, and the open shortcut) come through the guide's window: see
/// `OnboardingModel.handleKey`.
private struct StageInput: ViewModifier {
    let viewModel: IslandViewModel
    /// False on the steps whose stage is a picture (the menu bar, a banner).
    let isOn: Bool

    @State private var isDragTargeted = false

    func body(content: Content) -> some View {
        content
            // The island's own rectangle, which follows its size as it swells, peeks, and opens.
            .overlay(alignment: .top) {
                if isOn {
                    Color.clear
                        .frame(width: viewModel.hitSize.width, height: viewModel.hitSize.height)
                        .contentShape(Rectangle())
                        .onHover { viewModel.setHovering($0) }
                        .onTapGesture { if viewModel.state != .expanded { viewModel.open() } }
                        .accessibilityHidden(true)
                }
            }
            // Swipes anywhere on the stage, which is more forgiving than the notch-sized target the real island has.
            .background(PreviewSwipe { swipe in if isOn { viewModel.perform(swipe) } })
            // A dragged file shows the drop target. It is never dropped: the stage is practice, and a drop that added a file or
            // opened the AirDrop picker would be real.
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { _ in false }
            .onChange(of: isDragTargeted) { _, targeted in if isOn { viewModel.setFileDragActive(targeted) } }
    }
}

extension View {
    /// Makes an island drawn look-only (the guide's stage) answer to hover, a click, swipes, and a dragged file.
    func stageInput(_ viewModel: IslandViewModel, isOn: Bool) -> some View {
        modifier(StageInput(viewModel: viewModel, isOn: isOn))
    }
}
