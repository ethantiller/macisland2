import SwiftUI

/// The Layout section of the Home pane: what room is left, the presets (built in and saved), saving, and the file menu. The widgets
/// to add are `WidgetGallery`, and the selected widget's options are `WidgetInspector`. The canvas itself is the preview above
/// (`HomeGrid` with the editor in the environment).
struct HomeLayoutEditor: View {
    let editor: HomeEditor

    @State private var isSaving = false
    @State private var saveName = ""
    @State private var saveProblem: String?
    @FocusState private var nameIsFocused: Bool

    private var settings: AppSettings { editor.settings }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editor.layout.capacityText(catalog: editor.settings.widgetDescriptor(for:)))
                    if let refusal = editor.refusal {
                        Text(refusal)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                presets
                saveButton
                fileMenu
            }
        } header: {
            Text("Layout").id(SettingsAnchor.layout)
        } footer: {
            Text(
                "Drag widgets in the preview to arrange them and a corner to resize, or right-click one. Delete removes it, the arrows select, Option with an arrow moves it, \u{2318}] and \u{2318}[ change its size, and \u{2318}Z undoes. Save a layout you like and it joins the presets."
            )
        }
    }

    // MARK: Presets, saving, and files

    /// The built-in presets, then the ones the person saved, each with a button to remove it.
    private var presets: some View {
        StyledDropdown(accessibilityLabel: "Presets") {
            DropdownHeader("Presets")
            ForEach(HomeLayout.presets) { preset in
                DropdownItem(title: preset.name, isSelected: editor.layout.hasSameArrangement(as: preset.layout)) {
                    editor.applyPreset(preset)
                }
            }
            DropdownDivider()
            DropdownHeader("Saved")
            if settings.savedHomePresets.isEmpty {
                Text("Save a layout you like and it will be here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 190, alignment: .leading)
            } else {
                ForEach(settings.savedHomePresets) { saved in
                    DropdownItem(title: saved.name, isSelected: editor.layout.hasSameArrangement(as: saved.layout)) {
                        editor.applySaved(saved)
                    } trailing: {
                        Button {
                            editor.deleteSaved(saved.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(saved.name)")
                        .accessibilityLabel("Remove \(saved.name)")
                    }
                }
            }
        } label: {
            Text("Presets")
        }
    }

    /// Keeps the arrangement on Home, under a name, in the Presets menu.
    private var saveButton: some View {
        FieldButton(title: "Save", systemImage: "square.and.arrow.down") {
            saveName = SavedHomePreset.suggestedName(among: settings.savedHomePresets)
            saveProblem = nil
            isSaving = true
        }
        .popover(isPresented: $isSaving, arrowEdge: .bottom) { savePopover }
        .help("Save this layout as a preset")
    }

    private var savePopover: some View {
        let name = SavedHomePreset.cleaned(saveName)
        let replaces = settings.savedHomePresets.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Save This Layout")
                .font(.headline)
            TextField("Name", text: $saveName, prompt: Text("My Layout"))
                .textFieldStyle(.roundedBorder)
                .focused($nameIsFocused)
                .onSubmit(save)
                .onChange(of: saveName) { saveProblem = nil }
                .frame(width: 220)
            if let saveProblem {
                Text(saveProblem)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if replaces {
                Text("A saved layout with this name will be replaced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { isSaving = false }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
        }
        .padding(14)
        .onAppear { nameIsFocused = true }
    }

    private func save() {
        switch editor.saveLayout(named: saveName) {
        case .saved, .replaced: isSaving = false
        case .empty: saveProblem = "Give it a name."
        case .reserved: saveProblem = "That name belongs to a built-in preset."
        }
    }

    private var fileMenu: some View {
        StyledDropdown(accessibilityLabel: "More", showsChevron: false) {
            DropdownItem(title: "Export\u{2026}", systemImage: "square.and.arrow.up") {
                HomeArchivePanels.export(editor.layout, customs: settings.customWidgets)
            }
            DropdownItem(title: "Import\u{2026}", systemImage: "square.and.arrow.down.on.square") {
                if let plan = HomeArchivePanels.importPlan() {
                    for widget in plan.widgets { settings.saveCustomWidget(widget) }
                    editor.replace(with: plan.layout, actionName: "Import Layout")
                }
            }
            DropdownDivider()
            DropdownItem(title: "Reset to Everyday\u{2026}", systemImage: "arrow.counterclockwise") {
                if HomeArchivePanels.confirmReset() { editor.reset() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
        }
    }

}
