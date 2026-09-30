import SwiftUI
import Translation

/// The command palette: a query field over a short list of results, on Liquid Glass. It floats free of the
/// notch, so it follows the system appearance.
struct PaletteView: View {
    @Bindable var model: PaletteModel

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(Theme.Palette.secondary)
                    .accessibilityHidden(true)
                TextField("Search, or type a command", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.query)
                    .foregroundStyle(Theme.Palette.primary)
                    .focused($isFocused)
                    .accessibilityLabel("Command Palette")
            }
            .frame(height: 36)

            if !model.results.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        PaletteRow(item: item, isSelected: index == model.selection)
                            .onTapGesture {
                                model.selection = index
                                model.runSelected()
                            }
                    }
                }
            }
        }
        .frame(width: Theme.Metrics.paletteWidth - 2 * Theme.Metrics.floatPadding)
        .floatingGlass()
        .environment(\.islandSurface, .glass)
        .translationTask(model.translationConfiguration) { session in
            guard case .working(let request) = model.translation else { return }
            do {
                let response = try await session.translate(request.text)
                model.finishTranslation(request, output: response.targetText)
            } catch {
                model.finishTranslation(request, output: nil)
            }
        }
        .onAppear { isFocused = true }
    }
}

private struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.primary)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(
            isSelected ? Theme.Palette.fill : Theme.Palette.none,
            in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(Theme.Typography.glyph)
                .foregroundStyle(Theme.Palette.primary)
                .accessibilityHidden(true)
        case .app(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .accessibilityHidden(true)
        }
    }
}
