import SwiftUI

/// Add Widgets: everything that isn't on Home, as chips. Click a chip to see that widget at the size it would go in, drawn at 1:1 on black
/// (with the preview's own sample data); drag it into the island, or press its plus. There is one size: once it is on Home, a corner
/// drag resizes it. A widget that wouldn't fit at all says "No room". A chip's own plus adds it at the same size.
struct WidgetGallery: View {
    let editor: HomeEditor
    /// Where the previews get their data: the preview island's view model.
    let preview: IslandPreviewModel?
    /// The custom widget being made or edited, in a sheet the pane shows.
    @Binding var editing: CustomWidget?

    @State private var chosen: WidgetID?

    private var settings: AppSettings { editor.settings }
    private var catalog: HomeLayout.Catalog { settings.widgetDescriptor(for:) }

    private var addable: [WidgetID] {
        editor.layout.addable(customs: settings.customWidgets).filter { catalog($0) != nil }
    }

    /// The chip whose sizes are showing: the one clicked, or else the first.
    private func shown(in widgets: [WidgetID]) -> WidgetID? {
        chosen.flatMap { widgets.contains($0) ? $0 : nil } ?? widgets.first
    }

    var body: some View {
        let widgets = addable
        let open = shown(in: widgets)
        Section {
            if widgets.isEmpty {
                Text("Every widget is on Home.")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(widgets, id: \.self) { chip($0, isShown: $0 == open) }
                }
                if let open, let descriptor = catalog(open) { preview(of: open, descriptor) }
            }
            HStack {
                Button("New Widget\u{2026}") { editing = Self.blank }
                Spacer()
            }
        } header: {
            Text("Add Widgets").id(SettingsAnchor.widgets)
        } footer: {
            Text(
                editor.layout.capacityText(catalog: catalog) == "Home is full"
                    ? "Home is full. Make a widget smaller or remove one to add another."
                    : "Click a widget to see it. Drag it into the island, or press its plus; drag its corner there to resize it."
            )
        }
    }

    /// What \"New Widget\" starts from.
    static var blank: CustomWidget {
        CustomWidget(title: "", systemImage: "star", source: .shortcut(name: "", showsResult: true))
    }

    // MARK: Chips

    private func chip(_ widget: WidgetID, isShown: Bool) -> some View {
        let descriptor = catalog(widget)
        let fitsByDefault = editor.layout.fits(widget, size: editor.addSize(for: widget), catalog: catalog)
        return HStack(spacing: 4) {
            Button {
                chosen = widget
            } label: {
                Label(descriptor?.title ?? "Widget", systemImage: descriptor?.systemImage ?? "square")
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .frame(height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                editor.add(widget)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(fitsByDefault ? Color.accentColor : Color.secondary)
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!fitsByDefault)
            .help(fitsByDefault ? "Add \(descriptor?.title ?? "it") to Home" : "No room at its usual size")
            .accessibilityLabel("Add \(descriptor?.title ?? "Widget")")
        }
        .background(
            isShown ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08), in: Capsule()
        )
        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: isShown ? 1.5 : 0).allowsHitTesting(false))
        .contextMenu { customMenu(for: widget) }
        .accessibilityElement(children: .contain)
    }

    /// Edit and Delete, for a chip that is one of the person's own widgets.
    @ViewBuilder
    private func customMenu(for widgetID: WidgetID) -> some View {
        if case .custom(let id) = widgetID, let widget = settings.customWidget(id: id) {
            Button("Edit\u{2026}") { editing = widget }
            Button("Delete Widget", role: .destructive) { settings.removeCustomWidget(id) }
        }
    }

    // MARK: The preview

    /// The size a widget is added at from here: the size it last had, or its default, or else the smallest that fits. It is the one size
    /// shown; it is resized in the island, by dragging its corner.
    private func addedSize(of widget: WidgetID, _ descriptor: WidgetDescriptor) -> GridSize {
        let preferred = editor.addSize(for: widget)
        if editor.layout.fits(widget, size: preferred, catalog: catalog) { return preferred }
        return descriptor.sizes.filter { editor.layout.fits(widget, size: $0, catalog: catalog) }.min() ?? preferred
    }

    /// The widget as it would go in, on black like the island: drag it in, or press its plus.
    private func preview(of widget: WidgetID, _ descriptor: WidgetDescriptor) -> some View {
        let size = addedSize(of: widget, descriptor)
        let fits = editor.layout.fits(widget, size: size, catalog: catalog)
        let width = HomeGridSpec.width(columns: size.columns)
        let height = HomeGridSpec.height(rows: size.rows)
        return HStack(alignment: .bottom, spacing: 12) {
            Group {
                if let model = preview?.viewModel {
                    HomeWidgetView(
                        placement: WidgetPlacement(widget: widget, size: size), size: size, viewModel: model
                    )
                    .allowsHitTesting(false)
                } else {
                    Color.clear
                }
            }
            .frame(width: width, height: height)
            .opacity(fits ? 1 : 0.35)
            .overlay(Color.clear.contentShape(Rectangle()).gesture(drag(widget, size)))
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    editor.add(widget, size: size)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(fits ? Color.accentColor : Color.white.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!fits)
                .accessibilityLabel("Add \(descriptor.title)")
                Text(fits ? "Add, or drag it in" : "No room")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(fits ? 0.65 : 0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    /// Dragging the preview into the island: the widget lands at that size.
    private func drag(_ widget: WidgetID, _ size: GridSize) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(HomeEditor.space))
            .onChanged { value in
                if editor.gesture == nil { editor.beginAdd(widget, size: size, at: value.startLocation) }
                editor.update(to: value.location)
            }
            .onEnded { editor.end(at: $0.location) }
    }
}

/// Views in rows that wrap, left to right, with no scrolling sideways.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, in: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, in: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, in available: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + size.width
            if rows[rows.count - 1].width + needed > available, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows.removeLast()
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows.append(row)
        }
        return rows
    }
}
