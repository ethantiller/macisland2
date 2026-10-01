import SwiftUI

/// The Media module's options, shown in Content while Media is selected.
struct MediaOptions: View {
    let settings: AppSettings

    var body: some View {
        Group {
            Section {
                FeatureOffNote(settings: settings, feature: .music)
                Toggle("Show Music Beside the Notch", isOn: Bindable(settings).showsMusicCompact)
                    .tourAnchor(.musicCompact)
            } header: {
                Text("Music").id(SettingsAnchor.music)
            } footer: {
                Text(
                    "Off, music stays in the Home widget and the Media tab, and no longer appears while the island is collapsed."
                )
            }
            Section {
                SettingsDropdown(
                    title: "Show Media From", selection: Bindable(settings).mediaSource,
                    options: DropdownOption.all(MediaSource.allCases, title: \.rawValue))
            } footer: {
                Text(
                    "Music Apps Only ignores a video playing in a browser. macOS reports one player at a time, so this can\u{2019}t choose between two."
                )
            }
            Section {
                Toggle("Synced Lyrics", isOn: Bindable(settings).showsLyrics)
            } header: {
                Text("Lyrics").id(SettingsAnchor.lyrics)
            } footer: {
                Text("Looks up lyrics on lrclib.net using the track\u{2019}s name, artist, album, and length.")
            }
        }
    }
}
