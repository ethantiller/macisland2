import SwiftUI

struct GeneralPane: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
            }
            Section {
                ShortcutRecorder(settings: settings, slot: .open)
                    .tourAnchor(.shortcut)
            } header: {
                Text("Shortcut").id(SettingsAnchor.shortcut)
            } footer: {
                Text(
                    "Click it, then press the keys, with \u{2303}, \u{2325}, or \u{2318}. Delete turns it off. If another app already uses the keys, MacIsland says so and keeps the old ones."
                )
            }
            Section {
                Toggle("Peek on Hover", isOn: Bindable(settings).peeksOnHover)
                    .tourAnchor(.peekOnHover)
                Toggle("Swipe to Open and Switch Tabs", isOn: Bindable(settings).swipesEnabled)
                SettingsDropdown(
                    title: "Show the Island On", selection: Bindable(settings).islandDisplay,
                    options: DropdownOption.all(IslandDisplay.allCases, title: \.title))
            } header: {
                Text("Input").id(SettingsAnchor.input)
            } footer: {
                Text(
                    "Off, hovering only swells the island, and a click or a swipe opens it. Swiping needs a trackpad or Magic Mouse. The timer dial scrolls either way."
                )
            }
            Section {
                Button("Export Settings\u{2026}") { SettingsArchivePanels.export(settings) }
                Button("Import Settings\u{2026}") {
                    if let archive = SettingsArchivePanels.importArchive() { settings.restore(archive) }
                }
                Button("Reset All Settings\u{2026}", role: .destructive) {
                    if SettingsArchivePanels.confirmReset() { settings.resetAll() }
                }
            } header: {
                Text("Your Settings").id(SettingsAnchor.yourSettings)
            } footer: {
                Text(
                    "A file holds every choice on these panes, including Home. It never holds a widget that runs a program, and importing one never adds one."
                )
            }
        }
        .formStyle(.grouped)
    }
}
