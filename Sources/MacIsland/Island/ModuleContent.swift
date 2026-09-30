import SwiftUI

/// A module's view, wherever it is drawn: in the island, a menu-bar window, or a torn-off panel.
struct ModuleContent: View {
    let module: IslandModule
    let viewModel: IslandViewModel
    /// Where a dragged file is over the Shelf. Only the island has a drop target.
    var dropZone: DropZone?

    var body: some View {
        switch module {
        case .home:
            HomeView(viewModel: viewModel)
        case .media:
            if viewModel.nowPlaying.state.hasMedia {
                NowPlayingView(nowPlaying: viewModel.nowPlaying, outputs: viewModel.outputs)
            } else {
                Label("Not Playing", systemImage: "music.note")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .shelf:
            ShelfView(viewModel: viewModel, dropZone: dropZone)
        case .clock:
            ClockView(viewModel: viewModel)
        case .reminders:
            RemindersView(viewModel: viewModel)
        case .tools:
            ToolsView(viewModel: viewModel)
        case .notes:
            NotesView(viewModel: viewModel)
        case .agents:
            EmptyView()
        }
    }
}
