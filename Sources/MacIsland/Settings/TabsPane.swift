import SwiftUI

/// Where each tab goes, or (in the preview's Menu Bar view) which modules have an icon in the menu bar. Selecting a row shows that
/// tab in the preview.
struct TabsPane: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    var body: some View {
        Form {
            // The menu bar view shows only the menu bar's settings, and every other view only the tabs'.
            if preview?.context.presentation == .menuBar {
                MenuBarSection(settings: settings, preview: preview)
            } else {
                TabSection(settings: settings, side: .left, preview: preview)
                TabSection(settings: settings, side: .right, preview: preview)
            }
        }
        .formStyle(.grouped)
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
