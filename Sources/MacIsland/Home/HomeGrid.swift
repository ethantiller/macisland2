import AppKit
import SwiftUI

/// Home's widgets on a 6-column grid, laid out by `HomeLayout`. The island, the menu-bar and torn-off windows, and the
/// Settings editor all draw it, so Home looks the same everywhere. In the editor (`\.homeEditor` is set) each widget
/// stops taking clicks and gets editing chrome instead (`WidgetChrome`), and the grid takes the editor's keys.
struct HomeGrid: View {
    let layout: HomeLayout
    let viewModel: IslandViewModel

    @Environment(\.homeEditor) private var editor

    var body: some View {
        let catalog = viewModel.settings.widgetDescriptor(for:)
        let frames = layout.frames(catalog: catalog)
        ZStack(alignment: .topLeading) {
            if editor != nil {
                EmptyCells(
                    cells: HomeGridSpec.emptyCells(
                        layout.rects(catalog: catalog), rows: layout.rowsUsed(catalog: catalog))
                )
            }
            ForEach(layout.widgets) { placement in
                if let rect = frames[placement.id] {
                    let frame = HomeGridSpec.frame(of: rect)
                    cell(placement, size: rect.size)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(
            width: Theme.Metrics.homeContentWidth, height: layout.contentHeight(catalog: catalog),
            alignment: .topLeading
        )
        .animation(Theme.Motion.resize, value: layout)
        .modifier(EditorSupport(editor: editor))
    }

    @ViewBuilder
    private func cell(_ placement: WidgetPlacement, size: GridSize) -> some View {
        if let editor {
            HomeWidgetView(placement: placement, size: size, viewModel: viewModel)
                .allowsHitTesting(false)
                // The widget being dragged is a faint place-holder where it would land.
                .opacity(editor.dragging?.id == placement.id ? 0.35 : 1)
                .overlay { WidgetChrome(placement: placement, editor: editor) }
        } else {
            HomeWidgetView(placement: placement, size: size, viewModel: viewModel)
                .contextMenu {
                    if placement.widget == .builtIn(.notifications) {
                        Button("Clear Notifications") { viewModel.notifications.inbox.clear() }
                    }
                    Button("Edit Home\u{2026}") { viewModel.editHome(selecting: placement.id) }
                }
        }
    }
}

/// The grid in the editor: it tells the editor where it is (so a pointer can be turned into a cell) and takes its keys.
private struct EditorSupport: ViewModifier {
    let editor: HomeEditor?

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if let editor {
            content
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(HomeEditor.space))
                } action: {
                    editor.gridFrame = $0
                }
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onChange(of: editor.selection) { if editor.selection != nil { isFocused = true } }
                .onKeyPress(phases: [.down, .repeat]) { press in
                    guard let key = HomeKey(press) else { return .ignored }
                    return editor.perform(key) ? .handled : .ignored
                }
        } else {
            content
        }
    }
}

extension HomeKey {
    /// Delete removes the selected widget; the arrows select, with Option they move it; \u{2318}] and \u{2318}[ change its size;
    /// Escape calls a drag off.
    init?(_ press: KeyPress) {
        switch press.key {
        case .delete, .deleteForward: self = .delete
        case .escape: self = .escape
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            let direction: HomeMove =
                switch press.key {
                case .leftArrow: .left
                case .rightArrow: .right
                case .upArrow: .up
                default: .down
                }
            self = press.modifiers.contains(.option) ? .move(direction) : .select(direction)
        case KeyEquivalent("]") where press.modifiers.contains(.command): self = .nextSize
        case KeyEquivalent("[") where press.modifiers.contains(.command): self = .previousSize
        default: return nil
        }
    }
}

/// One widget at one size: the view that already exists for it, as `ModuleContent` maps a module to its view.
struct HomeWidgetView: View {
    let placement: WidgetPlacement
    /// The size it is drawn at: each size has its own layout.
    let size: GridSize
    let viewModel: IslandViewModel

    var body: some View {
        switch placement.widget {
        case .builtIn(.today): TimeWidget(viewModel: viewModel, size: size)
        case .builtIn(.music): MediaWidget(viewModel: viewModel, size: size)
        case .builtIn(.quickTools): QuickActionsGrid(viewModel: viewModel, chosen: placement.options.tools, size: size)
        case .builtIn(.clockActions): HomeActionPill(viewModel: viewModel, options: placement.options, size: size)
        case .builtIn(.weather): WeatherWidget(viewModel: viewModel, size: size)
        case .builtIn(.battery): BatteryWidget(size: size)
        case .builtIn(.system): SystemWidget(model: viewModel.system, size: size)
        case .builtIn(.agents):
            AgentsWidget(usage: viewModel.agents.usage, settings: viewModel.settings, size: size)
        case .builtIn(.notifications): NotificationsWidget(mirror: viewModel.notifications, size: size)
        case .builtIn(.reminders): RemindersWidget(viewModel: viewModel, size: size)
        case .builtIn(.note): NoteWidget(viewModel: viewModel, options: placement.options, size: size)
        case .custom(let id):
            if let widget = viewModel.settings.customWidget(id: id) {
                CustomWidgetView(widget: widget, viewModel: viewModel, size: size)
            }
        }
    }
}
