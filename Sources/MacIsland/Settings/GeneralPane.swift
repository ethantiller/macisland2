import SwiftUI

struct GeneralPane: View {
    let settings: AppSettings
    /// Shows the first-run guide again, and starts the Settings tour again. Set by the window that holds the pane.
    var onReplayGuide: () -> Void = {}
    var onReplayTour: () -> Void = {}

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
                ShortcutRecorder(settings: settings, slot: .shelf)
                    .tourAnchor(.shelfShortcut)
            } header: {
                Text("Shortcuts").id(SettingsAnchor.shortcut)
            } footer: {
                Text(
                    "Click it, then press the keys, with \u{2303}, \u{2325}, or \u{2318}. Delete turns it off. If another app already uses the keys, MacIsland says so and keeps the old ones."
                )
            }
            Section {
                Toggle("Peek on Hover", isOn: Bindable(settings).peeksOnHover)
                    .tourAnchor(.peekOnHover)
                SettingsDropdown(
                    title: "Peek After", selection: Bindable(settings).peekDelay,
                    options: DropdownOption.all(PeekDelay.allCases, title: \.rawValue)
                )
                .disabled(!settings.peeksOnHover)
                Toggle("Swipe to Open and Switch Tabs", isOn: Bindable(settings).swipesEnabled)
                SettingsDropdown(
                    title: "Show the Island On", selection: Bindable(settings).islandDisplay,
                    options: DropdownOption.all(IslandDisplay.allCases, title: \.title))
                Toggle("Hide the Island Until You Point at It", isOn: Bindable(settings).hidesUntilPointer)
                Toggle("Hide in Full Screen", isOn: Bindable(settings).hidesInFullScreen)
                SettingsDropdown(
                    title: "Open On", selection: Bindable(settings).openOn,
                    options: DropdownOption.all(OpenOn.allCases, title: \.rawValue))
            } header: {
                Text("Input").id(SettingsAnchor.input)
            } footer: {
                Text(
                    "Off, hovering only swells the island, and a click or a swipe opens it. Swiping needs a trackpad or Magic Mouse. The timer dial scrolls either way. Hidden, the island still opens when you point at the notch, and a banner or an alert still shows. Open On decides the page when the island opens from closed: the last one, Home, or the page of what is live."
                )
            }
            Section {
                HStack(spacing: 8) {
                    FieldButton(title: "Show the Welcome Guide", systemImage: "sparkles") { onReplayGuide() }
                    FieldButton(title: "Take the Settings Tour", systemImage: "hand.point.up.left") { onReplayTour() }
                }
                .tourAnchor(.guide)
            } header: {
                Text("Guide").id(SettingsAnchor.guide)
            } footer: {
                Text("The guide shows the gestures and modules again. The tour points out each pane\u{2019}s main controls.")
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
