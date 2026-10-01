import SwiftUI

struct ToolsView: View {
    let viewModel: IslandViewModel

    private var settings: AppSettings { viewModel.settings }
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.mirror.isOn {
                MirrorView(viewModel: viewModel)
            } else {
                if viewModel.toolsExpanded {
                    grid
                } else {
                    row
                }

                if viewModel.ringLight.isOn {
                    RingLightControls(light: viewModel.ringLight)
                        .transition(.opacity)
                }

                if viewModel.keepAwake.isOn {
                    KeepAwakeChips(keepAwake: viewModel.keepAwake)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            viewModel.micMute.refresh()
            viewModel.refreshInstalledShortcuts()
        }
    }

    /// The pinned tools, then a chevron for the rest.
    private var row: some View {
        HStack(spacing: 0) {
            ForEach(settings.visiblePinned) { toolButton($0) }
            // With every tool already in the row there is no more to show.
            if !settings.rowShowsEveryTool {
                IconButton(systemName: "chevron.down", label: "More Tools", size: 12) {
                    viewModel.setToolsExpanded(true)
                }
                .frame(height: 36)
                .padding(.leading, 4)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// Every tool, with Less in the last free slot.
    private var grid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
            ForEach(settings.allTools) { toolButton($0) }
            ControlButton(title: "Less", systemImage: "chevron.up") {
                viewModel.setToolsExpanded(false)
            }
        }
    }

    private func toolButton(_ id: ToolID) -> some View {
        ToolControlButton(tool: ToolCatalog(viewModel: viewModel).item(for: id))
            .contextMenu {
                if !settings.rowShowsEveryTool {
                    Button(settings.isPinned(id) ? "Unpin from Row" : "Pin to Row") {
                        settings.togglePin(id)
                    }
                }
                if let shortcutID = id.shortcutID {
                    Divider()
                    Button("Edit Shortcut Tool\u{2026}") { viewModel.editShortcutTool(shortcutID) }
                    Button("Remove Shortcut Tool", role: .destructive) { settings.removeShortcutTool(shortcutID) }
                }
            }
    }

}

/// A tool as a named round button: the Tools tab, and Quick Tools at its larger sizes.
struct ToolControlButton: View {
    let tool: ToolItem

    var body: some View {
        ControlButton(
            title: tool.title, systemImage: tool.systemImage, isOn: tool.isOn, accessibilityLabel: tool.label,
            action: tool.action
        )
        .disabled(!tool.isAvailable)
        .opacity(tool.isAvailable ? 1 : 0.4)
        .task(id: tool.id) { await tool.watch?() }
    }
}

/// Round Control Center-style button. On state is a white fill with a black glyph.
struct ControlButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    var accessibilityLabel: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(isOn ? Theme.Palette.inverse : Theme.Palette.primary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .background(
                        isOn ? Theme.Palette.primary : (isHovering ? Theme.Palette.fillHover : Theme.Palette.fill),
                        in: Circle()
                    )
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct RingLightControls: View {
    @Bindable var light: RingLight

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.max.fill")
            IslandSlider(value: light.brightness, label: "Ring Light Brightness", onChange: { light.brightness = $0 })
            Image(systemName: "arrow.left.and.right")
                .padding(.leading, 8)
            IslandSlider(value: light.width, label: "Ring Light Width", onChange: { light.width = $0 })
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.tertiary)
    }
}

/// How long Keep Awake lasts: until turned off, for an hour, or until a chosen hour.
private struct KeepAwakeChips: View {
    let keepAwake: KeepAwake

    private static let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)

    var body: some View {
        HStack(spacing: Theme.Metrics.rowSpacing) {
            ChipButton(title: "Indefinitely", isSelected: keepAwake.duration == .indefinitely) {
                keepAwake.start(.indefinitely)
            }
            ChipButton(title: "1 Hour", isSelected: keepAwake.duration == .hour) {
                keepAwake.start(.hour)
            }
            Menu {
                ForEach(KeepAwakeDuration.upcomingHours(from: Date()), id: \.self) { date in
                    Button(date.formatted(Self.timeFormat)) { keepAwake.start(.until(date)) }
                }
            } label: {
                ChipButton(title: untilTitle, isSelected: isUntil) {}
                    .allowsHitTesting(false)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Keep Awake Until")
            Spacer(minLength: 0)
        }
        .frame(height: Theme.Metrics.hitTarget)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var isUntil: Bool {
        if case .until = keepAwake.duration { true } else { false }
    }

    private var untilTitle: String {
        if case .until(let date) = keepAwake.duration { "Until \(date.formatted(Self.timeFormat))" } else { "Until…" }
    }
}
