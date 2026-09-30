import SwiftUI

struct ShelfPane: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    var body: some View {
        Form {
            Section {
                SettingsDropdown(
                    title: "When You Drag a File",
                    selection: Binding(
                        get: { settings.dragTarget },
                        set: {
                            settings.dragTarget = $0
                            preview?.show(SettingsPane.shelf.previewContext ?? PreviewContext())
                        }),
                    options: DropdownOption.all(DragTarget.allCases, title: \.title))
                Toggle("Add New Screenshots to the Shelf", isOn: Bindable(settings).addsScreenshots)
                SettingsDropdown(
                    title: "Remove Files from the Shelf", selection: Bindable(settings).shelfRetention,
                    options: DropdownOption.all(ShelfRetention.allCases, title: \.title))
            } header: {
                Text("Files").id(SettingsAnchor.files)
            } footer: {
                Text(
                    "Dragging a file toward the island makes it a slightly bigger target. Choose whether it goes to the Shelf, AirDrop, either half, or nowhere. Removing a file from the Shelf never deletes it, and it is checked when MacIsland starts and when the Shelf opens. Turning off screenshots also stops the search that finds them."
                )
            }
            Section {
                SettingsDropdown(
                    title: "Clipboard History", selection: Bindable(settings).clipboardLimit,
                    options: [DropdownOption(0, "Off")] + DropdownOption.all([10, 25, 50]) { "\($0) Items" })
            } header: {
                Text("Clipboard").id(SettingsAnchor.clipboard)
            } footer: {
                Text(
                    "Kept in memory only, and never written to disk. Copies that a password manager marks as private are skipped. Off, MacIsland stops watching the clipboard."
                )
            }
        }
        .formStyle(.grouped)
    }
}
