import SwiftUI

/// The selected widget's options. They appear only here, and their defaults reproduce today's Home, so most
/// people never see them.
struct WidgetInspector: View {
    let editor: HomeEditor
    let placement: WidgetPlacement
    /// The preview's view model, to name tools; and the real notes, to choose among.
    let preview: IslandViewModel
    let notes: NotesModel
    /// Edits a custom widget in its sheet.
    let onEdit: (CustomWidget) -> Void

    private static let timerChoices = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]

    private var descriptor: WidgetDescriptor? { editor.settings.widgetDescriptor(for: placement.widget) }
    private var options: WidgetOptions { placement.options }

    var body: some View {
        Section {
            sizePicker
            switch placement.widget {
            case .builtIn(.quickTools): quickTools
            case .builtIn(.clockActions): timersAndShelf
            case .builtIn(.note): note
            case .custom(let id): custom(id)
            default:
                if (descriptor?.sizes.count ?? 0) <= 1 {
                    Text("This widget has no options.")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Remove from Home", role: .destructive) { editor.remove(placement.id) }
        } header: {
            Text(descriptor?.title ?? "Widget")
        }
    }

    private func change(_ edit: (inout WidgetOptions) -> Void) {
        var new = options
        edit(&new)
        editor.setOptions(new, for: placement.id)
    }

    // MARK: Size

    /// One segment per size the widget has a layout for; a size that would leave something off Home is disabled.
    @ViewBuilder private var sizePicker: some View {
        if let sizes = descriptor?.sizes, sizes.count > 1, placement.widget != .builtIn(.quickTools) {
            LabeledContent("Size") {
                SettingsSegmented(
                    options: sizes.map { DropdownOption($0, $0.displayName) },
                    selection: Binding(
                        get: { placement.size },
                        set: { editor.setSize($0, for: placement.id) }),
                    isEnabled: { size in
                        size == placement.size
                            || editor.layout.resizing(
                                placement.id, to: size, catalog: editor.settings.widgetDescriptor(for:)) != nil
                    },
                    accessibilityLabel: "Size")
            }
        }
    }

    // MARK: Quick Tools

    /// Quick Tools shows up to eight tools you pick (6 by 2 shows every tool).
    @ViewBuilder private var quickTools: some View {
        let slots = min(8, QuickActionsGrid.toolCount(for: placement.size))
        if placement.size.rows >= 2 {
            Text("Shows every tool, as the Tools tab does.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Toggle(
                "Follow the Tools Row",
                isOn: Binding(
                    get: { options.tools == nil },
                    set: { follows in
                        change {
                            $0.tools =
                                follows
                                ? nil
                                : Array(
                                    QuickActionsGrid.tools(
                                        for: placement.size, chosen: nil, pinned: editor.settings.visiblePinned,
                                        all: editor.settings.allTools
                                    )
                                    .prefix(slots))
                        }
                    }))
            if let chosen = options.tools {
                let catalog = ToolCatalog(viewModel: preview)
                let tools = Self.filled(chosen, to: slots, from: editor.settings.allTools)
                ForEach(0..<slots, id: \.self) { slot in
                    SettingsDropdown(
                        title: "Tool \(slot + 1)",
                        selection: Binding(
                            get: { tools[slot] },
                            set: { tool in
                                change {
                                    var list = tools
                                    list[slot] = tool
                                    $0.tools = list
                                }
                            }),
                        options: DropdownOption.all(editor.settings.allTools) { catalog.item(for: $0).title })
                }
            } else {
                Text("Shows the first \(slots) tools in the Tools row.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The chosen tools, padded with the defaults to fill `count` slots.
    static func filled(_ chosen: [ToolID], to count: Int, from all: [ToolID] = ToolID.allCases) -> [ToolID] {
        var list = Array(chosen.filter(all.contains).prefix(count))
        let order = ToolID.fillOrder + all.filter { !ToolID.fillOrder.contains($0) }
        for tool in order where list.count < count && !list.contains(tool) && all.contains(tool) { list.append(tool) }
        return list
    }

    // MARK: Timers & Shelf

    @ViewBuilder private var timersAndShelf: some View {
        let minutes = options.timerMinutes ?? [5, 25]
        ForEach(0..<2, id: \.self) { slot in
            SettingsDropdown(
                title: slot == 0 ? "First Timer" : "Second Timer",
                selection: Binding(
                    get: { minutes.indices.contains(slot) ? minutes[slot] : [5, 25][slot] },
                    set: { value in
                        change {
                            var list = $0.timerMinutes ?? [5, 25]
                            list[slot] = value
                            $0.timerMinutes = list == [5, 25] ? nil : list
                        }
                    }),
                options: DropdownOption.all(Self.timerChoices) { "\($0) min" })
        }
        Toggle(
            "Show Pomodoro",
            isOn: Binding(
                get: { options.showsPomodoro ?? true },
                set: { value in change { $0.showsPomodoro = value ? nil : false } }))
        Toggle(
            "Show Shelf",
            isOn: Binding(
                get: { options.showsShelf ?? true },
                set: { value in change { $0.showsShelf = value ? nil : false } }))
    }

    // MARK: Note

    @ViewBuilder private var note: some View {
        SettingsDropdown(
            title: "Note",
            selection: Binding(
                get: { options.noteID },
                set: { id in change { $0.noteID = id } }),
            options: [DropdownOption<UUID?>(nil, "Latest Note")]
                + notes.notes.map { DropdownOption<UUID?>($0.id, $0.title) })
    }

    // MARK: Custom

    @ViewBuilder private func custom(_ id: UUID) -> some View {
        if let widget = editor.settings.customWidget(id: id) {
            LabeledContent("Source", value: widget.kindName)
            if let host = widget.webHost {
                LabeledContent("Asks", value: host)
            }
            HStack {
                Button("Edit\u{2026}") { onEdit(widget) }
                Button("Delete Widget", role: .destructive) { editor.settings.removeCustomWidget(id) }
            }
        }
    }
}
