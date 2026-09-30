import SwiftUI

struct MediaPane: View {
    let settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show Music Beside the Notch", isOn: Bindable(settings).showsMusicCompact)
            } header: {
                Text("Music").id(SettingsAnchor.music)
            } footer: {
                Text(
                    "Off, music stays in the Home widget and the Media tab, and no longer appears while the island is collapsed."
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
        .formStyle(.grouped)
    }
}
