import SwiftUI

/// The Tools module's options: how many tools the row shows, the tools made from Shortcuts, and the row's order. The sheet that edits a
/// Shortcut tool belongs to the Content pane (it also opens from the Tools tab's right-click menu).
struct ToolsOptions: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?
    @Binding var editing: ShortcutTool?

    var body: some View {
        Group {
            Section {
                LabeledContent("Tools in the Row") {
                    SettingsSegmented(
                        options: DropdownOption.all(PinLimit.allCases) { "\($0.rawValue)" },
                        selection: Bindable(settings).pinLimit, accessibilityLabel: "Tools in the Row")
                }
                .tourAnchor(.toolsRow)
            } header: {
                Text("Tools").id(SettingsAnchor.toolsRow)
            } footer: {
                Text(
                    "How many tools the Tools tab shows before More. Right-click a tool to pin it. Home\u{2019}s quick actions are the first four."
                )
            }
            Section {
                ForEach(settings.shortcutTools) { tool in
                    HStack(spacing: 10) {
                        Label(tool.title, systemImage: tool.systemImage)
                        Text(tool.shortcut)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Edit") { editing = tool }
                            .buttonStyle(.borderless)
                        Button("Remove", role: .destructive) { settings.removeShortcutTool(tool.id) }
                            .buttonStyle(.borderless)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button("Add Shortcut Tool\u{2026}") { editing = ShortcutTool(shortcut: "", title: "") }
                    .disabled(!settings.canAddShortcutTool)
            } header: {
                Text("Shortcut Tools").id(SettingsAnchor.shortcutTools)
            } footer: {
                Text(
                    "Make a tool from one of your Shortcuts: pressing it runs the Shortcut. Up to \(AppSettings.maxShortcutTools), which with the nine built in and Less fill the Tools tab. Its icon is one you choose here; MacIsland can\u{2019}t read the one Shortcuts shows."
                )
            }
            Section {
                ForEach(settings.visiblePinned) { tool in
                    ToolOrderRow(settings: settings, tool: tool, preview: preview)
                }
                DropTail { settings.movePinned($0, before: nil) }
            } header: {
                Text("Row Order").id(SettingsAnchor.rowOrder)
            } footer: {
                Text("Drag a tool to reorder the row. Right-click for Move Up and Move Down.")
            }
        }
    }
}

private struct ToolOrderRow: View {
    let settings: AppSettings
    let tool: ToolID
    let preview: IslandPreviewModel?

    var body: some View {
        let item = preview.map { ToolCatalog(viewModel: $0.viewModel).item(for: tool) }
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Label(item?.title ?? tool.rawValue, systemImage: item?.systemImage ?? "square")
            Spacer()
        }
        .contentShape(Rectangle())
        .draggable(tool.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(ToolID.init(rawValue:)) else { return false }
            settings.movePinned(dragged, before: tool)
            return true
        }
        .contextMenu {
            let row = settings.visiblePinned
            if let index = row.firstIndex(of: tool) {
                Button("Move Up") {
                    if index > 0 { settings.movePinned(tool, before: row[index - 1]) }
                }
                .disabled(index == 0)
                Button("Move Down") {
                    settings.movePinned(tool, before: index + 2 < row.count ? row[index + 2] : nil)
                }
                .disabled(index == row.count - 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The empty end of the list: where a dragged tool is dropped to go last.
private struct DropTail: View {
    let onDrop: (ToolID) -> Void

    var body: some View {
        Text("Drop a tool here to move it last")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let tool = items.first.flatMap(ToolID.init(rawValue:)) else { return false }
                onDrop(tool)
                return true
            }
    }
}
