import SwiftUI

/// The Shelf module's options: what a dragged file does, screenshots, how long files stay, and the clipboard's size.
struct ShelfOptions: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    /// What choosing what a dragged file does shows: the closed island with the drop target the choice gives.
    static let dragPreview = PreviewContext(presentation: .compact, tab: .shelf, fileDrag: true)

    var body: some View {
        Group {
            Section {
                SettingsDropdown(
                    title: "When You Drag a File",
                    selection: Binding(
                        get: { settings.dragTarget },
                        set: {
                            settings.dragTarget = $0
                            preview?.show(Self.dragPreview)
                        }),
                    options: DropdownOption.all(DragTarget.allCases, title: \.title)
                )
                .tourAnchor(.dragTarget)
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
                FeatureOffNote(settings: settings, feature: .clipboard)
                SettingsDropdown(
                    title: "Clipboard History", selection: Bindable(settings).clipboardLimit,
                    options: DropdownOption.all([10, 25, 50]) { "\($0) Items" }
                )
                .disabled(!settings.isOn(.clipboard))
            } header: {
                Text("Clipboard").id(SettingsAnchor.clipboard)
            } footer: {
                Text(
                    "Kept in memory only, and never written to disk. Copies that a password manager marks as private are skipped. Turn the Clipboard feature off in Features and MacIsland stops watching it."
                )
            }
        }
    }
}
