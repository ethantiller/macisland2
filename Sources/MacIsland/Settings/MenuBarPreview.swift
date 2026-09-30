import SwiftUI

/// The Menu Bar view of the Settings preview: a strip like the macOS menu bar with MacIsland's icon and one for each module
/// given its own, and under the chosen one the window it opens. Look-only, drawn from sample data. Clicking an icon shows
/// that module's window; which modules have an icon is chosen in the list below.
struct MenuBarPreview: View {
    let model: IslandPreviewModel
    /// How far the window has opened, from the strip (0) to full size (1).
    var reveal = 1.0

    private var settings: AppSettings { model.viewModel.settings }

    private static let order: [IslandModule] = [.home, .media, .shelf, .clock, .reminders, .tools, .notes]

    /// The module whose window is open: the one chosen in the list or by clicking an icon, whether or not it has an icon yet.
    private var shown: IslandModule { model.context.menuBarTab }

    /// The icons in the strip, in the order the menu bar puts them: the modules that have one, and the module being
    /// previewed even if it doesn't (as a ghost, so you can see where it would go).
    private var icons: [IslandModule] {
        Self.order.filter { settings.isInMenuBar($0) || $0 == shown }
    }

    var body: some View {
        VStack(spacing: 8) {
            strip
            if !settings.isInMenuBar(shown) { ghostNote }
            window(for: shown)
            Spacer(minLength: 0)
        }
    }

    /// Said when the module being previewed isn't in the menu bar yet.
    private var ghostNote: some View {
        Label("Not in the menu bar yet. Turn it on to add this icon.", systemImage: "plus.circle.dashed")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color.black.opacity(0.45), in: Capsule())
    }

    // MARK: The bar

    private var strip: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.logo")
                .font(.system(size: 13))
                .padding(.leading, 12)
            Text("Finder").font(.system(size: 12, weight: .semibold))
            Spacer()
            ForEach(icons) { module in icon(module) }
            Image(systemName: "capsule.fill")
                .font(.system(size: 13))
                .frame(width: 28, height: 22)
                .accessibilityLabel("MacIsland")
            Text("9:41")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .padding(.trailing, 12)
        }
        .foregroundStyle(.white)
        .frame(height: 26)
        .background(Color.black.opacity(0.55))
    }

    private func icon(_ module: IslandModule) -> some View {
        let isShown = module == shown
        let isGhost = !settings.isInMenuBar(module)
        return Button {
            model.showMenuBar(module)
        } label: {
            Image(systemName: module.systemImage)
                .font(.system(size: 13))
                .frame(width: 28, height: 22)
                .background(isShown ? Color.white.opacity(0.28) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    if isGhost {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
                .opacity(isGhost ? 0.7 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(module.title) in the menu bar")
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }

    // MARK: The window

    /// The module's menu-bar window, as it opens under its icon: a header, then the module on glass. Scaled down to fit when
    /// it is taller than the band.
    private func window(for module: IslandModule) -> some View {
        let viewModel = model.viewModel
        let content = viewModel.contentHeight(for: module)
        let padding = Theme.Metrics.floatPadding
        let full = Theme.Metrics.detachedChromeHeight + content + 2 * padding
        let room = Theme.Metrics.previewBandHeight - 26 - 8 - 8 - (settings.isInMenuBar(module) ? 0 : 30)
        let scale = min(1, room / full)
        return VStack(spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: 4) {
                Label(module.title, systemImage: module.systemImage)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                Spacer(minLength: 8)
                Image(systemName: "line.3.horizontal")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.tertiary)
                Image(systemName: "macwindow")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.Palette.primary)
                    .frame(width: Theme.Metrics.hitTarget, height: Theme.Metrics.hitTarget)
            }
            .frame(height: Theme.Metrics.detachedHeaderHeight)

            ModuleContent(module: module, viewModel: viewModel)
                .frame(width: Theme.Metrics.detachedWidth, height: content, alignment: .top)
        }
        .padding(padding)
        .frame(width: Theme.Metrics.detachedWidth + 2 * padding)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.Metrics.floatRadius))
        .environment(\.islandSurface, .glass)
        .environment(\.isFloatingWindow, true)
        .allowsHitTesting(false)
        .scaleEffect(scale * (0.55 + 0.45 * reveal), anchor: .top)
        .offset(y: (1 - reveal) * -8)
        .opacity(reveal)
        .frame(height: full * scale, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(module.title) window")
    }
}
