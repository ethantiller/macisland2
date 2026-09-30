import SwiftUI

/// The Settings window. Personal choices only.
struct SettingsView: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                Toggle("Quiet in Focus", isOn: Bindable(settings).quietDuringFocus)
                Picker("Shortcut", selection: Bindable(settings).hotkey) {
                    ForEach(HotkeyChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Calendar Events", isOn: Bindable(settings).showsCalendar)
                Toggle("Due Reminders", isOn: Bindable(settings).showsReminders)
            } header: {
                Text("Up Next")
            } footer: {
                Text("Meetings and due reminders show in Up Next on Home, and announce themselves as banners. The Reminders tab works either way.")
            }
            Section {
                TextField("City", text: Bindable(settings).weatherCity, prompt: Text("Paris"))
            } header: {
                Text("Weather")
            } footer: {
                Text("Shown beside the tabs and in the idle peek. Weather comes from Open-Meteo, which is sent only the city name.")
            }
            TabSection(settings: settings, side: .left)
            TabSection(settings: settings, side: .right)
            HiddenTabsSection(settings: settings)
            MenuBarSection(settings: settings)
            SearchSection(settings: settings)
            Section {
                Toggle("Synced Lyrics", isOn: Bindable(settings).showsLyrics)
            } header: {
                Text("Media")
            } footer: {
                Text("Looks up lyrics on lrclib.net using the track\u{2019}s name, artist, album, and length.")
            }
            Section("Battery") {
                Picker("Full Charge Alert", selection: Bindable(settings).fullChargeLevel) {
                    ForEach(Array(stride(from: 80, through: 100, by: 5)), id: \.self) { Text("\($0)%").tag($0) }
                }
            }
            Section {
                Picker("Tools in the Row", selection: Bindable(settings).pinLimit) {
                    ForEach(PinLimit.allCases) { Text("\($0.rawValue)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Tools")
            } footer: {
                Text("How many tools the Tools tab shows before More. Right-click a tool to pin it. Home\u{2019}s quick actions are the first four.")
            }
        }
        .formStyle(.grouped)
        // The form scrolls, and the window can be resized to whatever fits the screen.
        .frame(minWidth: 420, idealWidth: 460, maxWidth: 640, minHeight: 320, idealHeight: 560, maxHeight: .infinity)
        .onAppear { settings.refresh() }
    }
}

// MARK: Tabs

/// One side of the notch: its tabs in order, each draggable to reorder or to move to another list, with an
/// on/off switch. Turning one off moves it to Not Shown.
private struct TabSection: View {
    let settings: AppSettings
    let side: AppSettings.TabSide

    private var title: String { side == .left ? "Left of the Notch" : "Right of the Notch" }

    var body: some View {
        let tabs = settings.tabs(on: side)
        Section {
            ForEach(tabs) { module in
                TabRow(settings: settings, module: module)
            }
            if settings.hasRoom(on: side) {
                DropPlaceholder(text: "Drop a tab here") { module in
                    settings.move(module, to: side)
                }
            }
        } header: {
            Text("\(title) (\(tabs.count) of \(side.capacity))")
        } footer: {
            Text(side == .left
                ? "Up to \(Theme.Metrics.maxTabs) tabs. Drag a tab to reorder it, or onto another list."
                : "One tab, beside Settings. It leaves room for the timer, and the New Note pencil and weather step aside when there isn\u{2019}t any.")
        }
    }
}

/// Modules that aren't tabs. Turning one on puts it on the left, or the right if the left is full.
private struct HiddenTabsSection: View {
    let settings: AppSettings

    var body: some View {
        Section {
            ForEach(settings.hiddenModules) { module in
                TabRow(settings: settings, module: module)
            }
            DropPlaceholder(text: "Drop a tab here to turn it off") { module in
                settings.setEnabled(module, false)
                return !settings.isInTabs(module)
            }
        } header: {
            Text("Not Shown")
        } footer: {
            Text("These still open another way: the pencil beside the tabs opens Notes, dropping a file opens Shelf, and the command palette finds everything.")
        }
    }
}

private struct TabRow: View {
    let settings: AppSettings
    let module: IslandModule

    private var side: AppSettings.TabSide? { settings.side(of: module) }

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
            Toggle("Show \(module.title)", isOn: Binding(
                get: { side != nil },
                set: { settings.setEnabled(module, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(side == nil ? !settings.canAddTab : settings.tabs.count <= 1)
        }
        .contentShape(Rectangle())
        .draggable(module.rawValue)
        // Dropping another tab on this row puts it just before this one, on this row's side.
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(IslandModule.init(rawValue:)) else { return false }
            guard let side else { return settings.setEnabledReturning(dragged, false) }
            return settings.move(dragged, to: side, before: module)
        }
        .contextMenu {
            if let side {
                Button("Move Up") { settings.nudge(module, by: -1) }
                Button("Move Down") { settings.nudge(module, by: 1) }
                Button(side == .left ? "Move to Right" : "Move to Left") {
                    settings.move(module, to: side == .left ? .right : .left)
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

// MARK: Menu bar and search

/// Put a module in the menu bar. None are there until you choose.
private struct MenuBarSection: View {
    let settings: AppSettings

    var body: some View {
        Section {
            ForEach(IslandModule.allCases.filter(\.isAvailable)) { module in
                Toggle(isOn: Binding(
                    get: { settings.isInMenuBar(module) },
                    set: { settings.setInMenuBar(module, $0) }
                )) {
                    Label(module.title, systemImage: module.systemImage)
                }
            }
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Each one adds an icon that opens the module. Drag its header away to pop it out into a window; Keep on Desktop puts that window just above the desktop icons. You can also right-click a tab.")
        }
    }
}

/// The command palette's web search: which engine it uses, and engines of your own.
private struct SearchSection: View {
    let settings: AppSettings

    @State private var name = ""
    @State private var keyword = ""
    @State private var template = ""

    var body: some View {
        Section {
            Picker("Search With", selection: Bindable(settings).defaultSearchEngineID) {
                ForEach(settings.searchEngines) { engine in
                    Text("\(engine.name)  (\(engine.keyword))").tag(engine.id)
                }
            }
            ForEach(settings.customEngines) { engine in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(engine.name)  (\(engine.keyword))")
                        Text(engine.template)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { settings.removeCustomEngine(engine.id) }
                        .buttonStyle(.borderless)
                }
            }
            TextField("Name", text: $name, prompt: Text("Kagi"))
            TextField("Keyword", text: $keyword, prompt: Text("k"))
            TextField("Address", text: $template, prompt: Text("https://kagi.com/search?q=%s"))
            Button("Add Search Engine") {
                if settings.addCustomEngine(name: name, keyword: keyword, template: template) {
                    name = ""
                    keyword = ""
                    template = ""
                }
            }
            .disabled(name.isEmpty || keyword.isEmpty || !SearchEngine.isValid(template: template))
        } header: {
            Text("Command Palette Search")
        } footer: {
            Text("Press \u{2303}\u{2325}K, then type a keyword and a search, like \u{201C}yt swift\u{201D}. Use %s in an address where the search goes. Type \u{201C}tr hello\u{201D} to translate, or \u{201C}tr es hello\u{201D} to pick the language.")
        }
    }
}
