import SwiftUI

/// Content: where each tab goes, which modules are on, and the selected module's own options beside them. In the preview's Menu Bar
/// view it is which modules have an icon in the menu bar. Selecting a row, a tab in the preview, or a tray tab shows that tab in the
/// preview and its options here.
struct TabsPane: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    /// The Shortcut tool whose sheet is showing. It lives here because the Tools tab's right-click menu can ask for it from outside.
    @State private var editingTool: ShortcutTool?
    @Environment(\.openPane) private var openPane

    /// What the preview shows for a module's options: its tab, and for Clock the Pomodoro its options are about.
    static func previewContext(for module: IslandModule) -> PreviewContext {
        .options(for: module)
    }

    /// The module whose options show: the tab the preview is on, or Home when that module has been turned off.
    var selected: IslandModule {
        let tab = preview?.context.tab ?? .home
        return settings.isShown(tab) ? tab : .home
    }

    var body: some View {
        Form {
            // The menu bar view shows only the menu bar's settings, and every other view only the tabs'.
            if preview?.context.presentation == .menuBar {
                MenuBarSection(settings: settings, preview: preview)
            } else {
                TabSection(settings: settings, side: .left, preview: preview)
                TabSection(settings: settings, side: .right, preview: preview)
                OffInFeaturesSection(settings: settings)
                moduleOptions(for: selected)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingTool) { tool in
            ShortcutToolSheet(tool: tool) { settings.saveShortcutTool($0) }
        }
        // The Tools tab's right-click menu asks for a tool's sheet: show Tools, and the sheet.
        .task(id: settings.requestedShortcutToolEdit) {
            guard let id = settings.requestedShortcutToolEdit else { return }
            settings.requestedShortcutToolEdit = nil
            preview?.show(Self.previewContext(for: .tools))
            editingTool = settings.shortcutTool(id: id)
        }
    }

    @ViewBuilder private func moduleOptions(for module: IslandModule) -> some View {
        switch module {
        case .home:
            Section {
                Text("Home is arranged in the Home pane, where its widgets are added, moved, and resized.")
                    .foregroundStyle(.secondary)
                Button("Open Home") { openPane(.home) }
            } header: {
                Text("Home").id(SettingsAnchor.options)
            }
        case .media: MediaOptions(settings: settings)
        case .clock: ClockOptions(settings: settings, preview: preview)
        case .shelf: ShelfOptions(settings: settings, preview: preview)
        case .tools: ToolsOptions(settings: settings, preview: preview, editing: $editingTool)
        case .reminders:
            Section {
                FeatureOffNote(settings: settings, feature: .reminders)
                Toggle("Due Reminders in Up Next", isOn: Bindable(settings).showsReminders)
                    .disabled(!settings.isOn(.reminders))
            } header: {
                Text("Reminders").id(SettingsAnchor.dueReminders)
            } footer: {
                Text(
                    "Due reminders show in Up Next on Home, and announce themselves as banners. The Reminders tab works either way."
                )
            }
        case .notes:
            Section {
                Text("Notes has no options.").foregroundStyle(.secondary)
            } header: {
                Text("Notes").id(SettingsAnchor.options)
            }
        case .agents: AgentsOptions(settings: settings, preview: preview)
        }
    }
}

/// Modules whose feature is off: not draggable, and a way to the switch.
private struct OffInFeaturesSection: View {
    let settings: AppSettings
    @Environment(\.openFeatures) private var openFeatures

    private var off: [IslandModule] {
        IslandModule.allCases.filter { $0.isAvailable && !settings.isShown($0) }
    }

    var body: some View {
        if !off.isEmpty {
            Section {
                ForEach(off) { module in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(module.title, systemImage: module.systemImage)
                            Text("Turned off in Features.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let feature = Feature.module(for: module) {
                            Button("Open Features") { openFeatures(feature) }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Off in Features")
            } footer: {
                Text("A module that is off has no tab, no menu bar icon, and runs nothing. Its place in the strip is kept.")
            }
        }
    }
}

/// One side of the notch: its tabs in order, each draggable to reorder or to move to another list, with an
/// on/off switch. Turning one off moves it to the Not Shown tray under the preview.
struct TabSection: View {
    let settings: AppSettings
    let side: AppSettings.TabSide
    let preview: IslandPreviewModel?

    private var title: String { side == .left ? "Left of the Notch" : "Right of the Notch" }

    var body: some View {
        let tabs = settings.shownTabs(on: side)
        Section {
            ForEach(tabs) { module in
                TabRow(settings: settings, module: module, preview: preview)
            }
            if settings.hasRoom(on: side) {
                DropPlaceholder(text: "Drop a tab here") { module in
                    settings.move(module, to: side)
                }
            }
        } header: {
            Text("\(title) (\(tabs.count) of \(side.capacity))")
        } footer: {
            Text(
                side == .left
                    ? "Up to \(Theme.Metrics.maxTabs) tabs. Reorder them here, or drag them in the preview above; tabs that are not shown wait in the tray under it."
                    : "One tab, beside Settings. It leaves room for the timer, and the New Note pencil and weather step aside when there isn\u{2019}t any."
            )
        }
    }
}

private struct TabRow: View {
    let settings: AppSettings
    let module: IslandModule
    let preview: IslandPreviewModel?

    private var side: AppSettings.TabSide? { settings.side(of: module) }

    private var isSelected: Bool {
        preview?.context.presentation == .expanded && preview?.context.tab == module
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Label(module.title, systemImage: module.systemImage)
                if side == nil, let hint = module.otherWayIn {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Toggle(
                "Show \(module.title)",
                isOn: Binding(
                    get: { side != nil },
                    set: { settings.setEnabled(module, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(side == nil ? !settings.canAddTab : settings.shownTabs.count <= 1)
        }
        .padding(.vertical, 2)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        // Clicking a row shows that tab in the preview, as clicking a notification does.
        .onTapGesture { preview?.show(PreviewContext(presentation: .expanded, tab: module)) }
        .draggable(module.rawValue)
        // Dropping a tab on this row takes this row's place; on a full side the two swap.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(IslandModule.init(rawValue:)) else { return false }
            guard side != nil else { return settings.setEnabledReturning(dragged, false) }
            let done = settings.placeTab(dragged, before: module)
            if done { preview?.show(PreviewContext(presentation: .expanded, tab: dragged)) }
            return done
        }
        .contextMenu {
            if let side {
                Button("Move Up") { settings.nudge(module, by: -1) }
                Button("Move Down") { settings.nudge(module, by: 1) }
                Button(side == .left ? "Move to Right" : "Move to Left") {
                    settings.moveTab(module, toSide: side == .left ? .right : .left)
                }
                Divider()
                Button("Turn Off") { settings.setEnabled(module, false) }
            } else {
                Button("Turn On") { settings.setEnabled(module, true) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The empty end of a list: where a dragged tab can be dropped to go last.
private struct DropPlaceholder: View {
    let text: String
    let onDrop: (IslandModule) -> Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let module = items.first.flatMap(IslandModule.init(rawValue:)) else { return false }
                return onDrop(module)
            }
    }
}

/// Put a module in the menu bar. None are there until you choose.
private struct MenuBarSection: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    /// Only modules that are on can have an icon.
    private var shown: [IslandModule] { IslandModule.allCases.filter(settings.isShown) }

    var body: some View {
        Section {
            ForEach(shown) { module in
                row(module)
                    .tourAnchor(module == shown.first ? .menuBarRow : nil)
            }
        } header: {
            Text("Menu Bar").id(SettingsAnchor.menuBar)
        } footer: {
            Text(
                "Click a module to see its window, on or off. The switch gives it its own icon. Drag a window\u{2019}s header away to pop it out; Keep on Desktop puts that window just above the desktop icons. You can also right-click a tab."
            )
        }
    }

    /// The row previews the module when clicked (turned on or not); the switch adds or removes its icon.
    private func row(_ module: IslandModule) -> some View {
        let isSelected = preview?.context.presentation == .menuBar && preview?.context.menuBarTab == module
        return HStack(spacing: 10) {
            Label(module.title, systemImage: module.systemImage)
            Spacer(minLength: 8)
            Toggle(
                "Show \(module.title) in the Menu Bar",
                isOn: Binding(
                    get: { settings.isInMenuBar(module) },
                    set: {
                        settings.setInMenuBar(module, $0)
                        preview?.showMenuBar(module)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { preview?.showMenuBar(module) }
        .accessibilityElement(children: .combine)
    }
}

/// The AI Agents module's options: which agents are read, whether a working one shows beside the notch, and the shortest task that
/// gets a notice.
struct AgentsOptions: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    /// What the preview shows for one tool on its own: the view it is on when that shows the tool (Compact, Peek, Banner, or Expanded),
    /// else Expanded, where Agents opens on Stats filtered to it.
    static func previewContext(for agent: AgentKind, from current: PreviewContext) -> PreviewContext {
        let keeps: [PreviewPresentation] = [.compact, .peek, .banner, .expanded]
        let presentation = keeps.contains(current.presentation) ? current.presentation : .expanded
        return PreviewContext(
            presentation: presentation, tab: .agents, event: .agentDone, agent: agent, agentsMode: .stats,
            lead: .activity("agent"))
    }

    var body: some View {
        Section {
            FeatureOffNote(settings: settings, feature: .agents)
            ForEach(AgentKind.allCases) { agent in
                HStack(spacing: 10) {
                    // The name previews the tool on the island; the switch is for reading it.
                    Button {
                        guard let preview else { return }
                        preview.show(Self.previewContext(for: agent, from: preview.context))
                    } label: {
                        HStack(spacing: 10) {
                            AgentMark(agent: agent, size: 18)
                            Text(agent.rawValue)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Previews \(agent.rawValue) on the island")
                    Toggle(
                        agent.rawValue,
                        isOn: Binding(get: { settings.reads(agent) }, set: { settings.setReads(agent, $0) })
                    )
                    .labelsHidden()
                    // At least one stays on.
                    .disabled(settings.reads(agent) && AgentKind.allCases.filter(settings.reads).count == 1)
                }
            }
            Toggle("Show a Working Agent Beside the Notch", isOn: Bindable(settings).showsAgentCompact)
            SettingsDropdown(
                title: "Tell Me When a Task Finishes", selection: Bindable(settings).agentFinishMinimum,
                options: AppSettings.agentMinimums.map { DropdownOption($0, Self.words($0)) })
            SettingsDropdown(
                title: "Tell Me When a Plan Limit Is Near", selection: Bindable(settings).agentLimitThreshold,
                options: AppSettings.agentThresholds.map { DropdownOption($0, "At \($0)%") })
            Toggle("Show Limits as What\u{2019}s Left", isOn: Bindable(settings).showsLimitsLeft)
        } header: {
            Text("AI Agents").id(SettingsAnchor.agents)
        } footer: {
            Text(
                "Click Claude Code or Codex to preview it. Read from the logs Claude Code and Codex keep in your home folder, and from the Claude app\u{2019}s usage file when it has one. Nothing is sent."
            )
        }
    }

    /// "After 30 seconds", "After 1 minute", "After 2 minutes".
    static func words(_ seconds: Int) -> String {
        seconds < 60 ? "After \(seconds) seconds" : (seconds == 60 ? "After 1 minute" : "After \(seconds / 60) minutes")
    }
}
