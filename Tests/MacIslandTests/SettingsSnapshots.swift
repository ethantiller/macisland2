import AppKit
import SwiftUI
import Testing

@testable import MacIsland

/// Renders the Settings preview for each pane's context, for design review. Opt-in, like `IslandSnapshots`:
/// `ISLAND_SNAPSHOT_DIR=/some/dir ./scripts/test.sh --filter SettingsSnapshots`. `ImageRenderer` can't draw
/// `Form`s reliably, so the panes themselves are checked in the app.
@MainActor
struct SettingsSnapshots {
    private let outputDirectory = ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"].map(
        URL.init(fileURLWithPath:))

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderPreviews() async throws {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.viewModel.geometry = live.geometry
        try await Task.sleep(for: .milliseconds(150))

        for pane in SettingsPane.allCases {
            guard let context = pane.previewContext else { continue }
            preview.show(context, animated: false)
            render(preview, "20-settings-\(pane.rawValue)")
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderHomeEditor() async throws {
        let live = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.viewModel.geometry = live.geometry
        let editor = HomeEditor(settings: live.settings)
        editor.previewModel = preview
        try await Task.sleep(for: .milliseconds(150))
        preview.show(PreviewContext(presentation: .expanded, tab: .home), animated: false)
        editor.selection = live.settings.homeLayout.widgets[1].id
        render(preview, "21-settings-home-editor", editor: editor)
        // A Home with a gap and room: Music at 2 by 1 leaves a cell in row 1.
        live.settings.setHomeLayout(
            HomeLayout(widgets: [
                WidgetPlacement(widget: .builtIn(.today), size: GridSize(3, 1)),
                WidgetPlacement(widget: .builtIn(.music), size: GridSize(2, 1)),
            ]))
        render(preview, "21-settings-home-editor-room", editor: editor)
    }

    /// Add Widgets: the chips and the sizes of one, on black. Drawn outside a Form (which renders blank offscreen), so the section headers are missing.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderGallery() async throws {
        guard let outputDirectory else { return }
        let live = TestSupport.makeViewModel()
        live.settings.setHomeLayout(HomeLayout.presets[3].layout)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        let editor = HomeEditor(settings: live.settings)
        editor.previewModel = preview
        try await Task.sleep(for: .milliseconds(150))
        let content = VStack(alignment: .leading, spacing: 12) {
            WidgetGallery(editor: editor, preview: preview, editing: .constant(nil))
        }
        .padding(20)
        .frame(width: 640, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: content.environment(\.isSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("21-settings-home-gallery.png"))
    }

    /// The styled dropdown: the field closed, and the list a popover would hold (a popover itself can't be rendered).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderDropdown() {
        guard let outputDirectory else { return }
        let (settings, _) = (TestSupport.makeViewModel().settings, 0)
        settings.setHomeLayout(.default)
        settings.saveHomePreset(named: "Night Mode")
        settings.saveHomePreset(named: "Work")
        let content = VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Spacer()
                StyledDropdown(accessibilityLabel: "Presets") {
                    EmptyView()
                } label: {
                    Text("Presets")
                }
                FieldButton(title: "Save", systemImage: "square.and.arrow.down") {}
                StyledDropdown(accessibilityLabel: "More") {
                    EmptyView()
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .frame(width: 420)
            VStack(alignment: .leading, spacing: 2) {
                DropdownHeader("Presets")
                ForEach(HomeLayout.presets) { preset in
                    DropdownItem(title: preset.name, isSelected: preset.name == "Everyday") {}
                }
                DropdownDivider()
                DropdownHeader("Saved")
                ForEach(settings.savedHomePresets) { saved in
                    DropdownItem(title: saved.name) {
                    } trailing: {
                        Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding(6)
            .frame(width: 210, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: content.environment(\.isSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("22-settings-dropdown.png"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_SNAPSHOT_DIR"] != nil))
    func renderMenuBar() async throws {
        let live = TestSupport.makeViewModel()
        live.settings.setInMenuBar(.home, true)
        live.settings.setInMenuBar(.clock, true)
        live.settings.setInMenuBar(.notes, true)
        let preview = IslandPreviewModel(live: live.features)
        defer { preview.stop() }
        preview.allowsMenuBar = true
        preview.show(PreviewContext(presentation: .menuBar, menuBarTab: .home), animated: false)
        render(preview, "20-settings-menubar")
        preview.show(PreviewContext(presentation: .menuBar, menuBarTab: .reminders), animated: false)
        render(preview, "20-settings-menubar-ghost")
    }

    private func render(_ preview: IslandPreviewModel, _ name: String, editor: HomeEditor? = nil) {
        guard let outputDirectory else { return }
        let content = IslandPreview(model: preview, editor: editor)
            .frame(width: 640)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: content.environment(\.isSnapshot, true))
        renderer.scale = 2
        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
