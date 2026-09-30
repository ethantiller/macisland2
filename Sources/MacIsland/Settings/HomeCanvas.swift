import SwiftUI

// The Home editor's chrome: what is drawn over the preview while Home is being edited. It is Settings chrome, in the system
// accent color, and is never drawn on the island itself.

// MARK: On each widget

/// Over one widget: selection and hover rings, the remove badge, the resize handle, the drag that moves it, the context menu,
/// and the VoiceOver actions that do everything a drag does.
struct WidgetChrome: View {
    let placement: WidgetPlacement
    let editor: HomeEditor

    @State private var isHovering = false

    private var descriptor: WidgetDescriptor? { editor.settings.widgetDescriptor(for: placement.widget) }
    private var title: String { descriptor?.title ?? "Widget" }
    private var catalog: HomeLayout.Catalog { editor.settings.widgetDescriptor(for:) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
        let isSelected = editor.selection == placement.id
        // The widget being dragged leaves a faint slot where it would land.
        let isLanding = editor.dragging?.id == placement.id
        ZStack {
            Color.clear
                .contentShape(shape)
                .gesture(moveDrag)
                .onTapGesture { editor.selection = placement.id }
            shape
                .strokeBorder(
                    Color.accentColor.opacity(isSelected || isLanding ? 1 : 0.55),
                    lineWidth: isSelected || isLanding ? 2 : (isHovering ? 1.5 : 0)
                )
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) { badge }
        .overlay(alignment: .bottomTrailing) { handle }
        .onHover { isHovering = $0 }
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(placement.size.columns) by \(placement.size.rows)")
        .accessibilityValue(position)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move Left") { editor.move(placement.id, .left) }
        .accessibilityAction(named: "Move Right") { editor.move(placement.id, .right) }
        .accessibilityAction(named: "Move Up") { editor.move(placement.id, .up) }
        .accessibilityAction(named: "Move Down") { editor.move(placement.id, .down) }
        .accessibilityAction(named: "Make Larger") { editor.stepSize(placement.id, by: 1) }
        .accessibilityAction(named: "Make Smaller") { editor.stepSize(placement.id, by: -1) }
        .accessibilityAction(named: "Remove") { editor.remove(placement.id) }
    }

    /// "row 2, column 1", for VoiceOver.
    private var position: String {
        guard let rect = editor.layout.frames(catalog: catalog)[placement.id] else { return "" }
        return "row \(rect.origin.row + 1), column \(rect.origin.column + 1)"
    }

    // MARK: Gestures

    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(HomeEditor.space))
            .onChanged { value in
                if editor.gesture == nil { editor.beginMove(placement.id, at: value.startLocation) }
                editor.update(to: value.location)
            }
            .onEnded { editor.end(at: $0.location) }
    }

    private var resizeDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(HomeEditor.space))
            .onChanged { value in
                if editor.gesture == nil { editor.beginResize(placement.id, at: value.startLocation) }
                editor.updateResize(to: value.location)
            }
            .onEnded { _ in editor.endResize() }
    }

    // MARK: Parts

    /// Remove: always there while editing, and dimmed on the last widget (Home keeps one).
    private var badge: some View {
        Button {
            editor.remove(placement.id)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: Theme.Metrics.editorBadge))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .frame(width: Theme.Metrics.editorHandle, height: Theme.Metrics.editorHandle)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(editor.layout.widgets.count > 1 ? 1 : 0.35)
        .offset(x: -12, y: -12)
        .accessibilityHidden(true)
    }

    /// The corner you drag to resize, for a widget that has more than one size.
    @ViewBuilder private var handle: some View {
        if (descriptor?.sizes.count ?? 0) > 1 {
            CornerGrip()
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 10, height: 10)
                .frame(
                    width: Theme.Metrics.editorHandle, height: Theme.Metrics.editorHandle, alignment: .bottomTrailing
                )
                .padding(5)
                .contentShape(Rectangle())
                .gesture(resizeDrag)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Move Left") { editor.move(placement.id, .left) }
        Button("Move Right") { editor.move(placement.id, .right) }
        Button("Move Up") { editor.move(placement.id, .up) }
        Button("Move Down") { editor.move(placement.id, .down) }
        if let sizes = descriptor?.sizes, sizes.count > 1 {
            Menu("Size") {
                ForEach(sizes, id: \.self) { size in
                    Toggle(
                        size.displayName,
                        isOn: Binding(
                            get: { size == placement.size }, set: { _ in editor.setSize(size, for: placement.id) })
                    )
                    .disabled(
                        size != placement.size
                            && editor.layout.resizing(placement.id, to: size, catalog: catalog) == nil)
                }
            }
        }
        Divider()
        Button("Remove", role: .destructive) { editor.remove(placement.id) }
    }
}

/// Two short diagonal strokes in a corner: the resize handle's mark.
private struct CornerGrip: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY + 1))
        path.addLine(to: CGPoint(x: rect.midX + 1, y: rect.maxY))
        return path
    }
}

// MARK: Cells and room

/// A dashed outline for each empty cell in the rows Home uses, so a gap reads as a place to drop.
struct EmptyCells: View {
    let cells: [GridCell]

    var body: some View {
        ForEach(cells, id: \.self) { cell in
            let frame = HomeGridSpec.frame(of: GridRect(origin: cell, size: GridSize(1, 1)))
            RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
    }
}

/// The island's room to grow, dashed behind the island in the preview band: its outline at full height, the empty cells of the
/// rows Home could still take, and how many there are. Nothing when Home is full.
struct HomeRoom: View {
    let layout: HomeLayout
    let catalog: HomeLayout.Catalog
    /// The notch and the gap under it: where Home's grid starts.
    let headerHeight: CGFloat

    var body: some View {
        let used = layout.rowsUsed(catalog: catalog)
        let rows = Theme.Metrics.homeMaxRows
        if used < rows {
            let left = rows - used
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Metrics.expandedRadius, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
                    .frame(
                        width: Theme.Metrics.expandedWidth,
                        height: headerHeight + Theme.Metrics.homeMaxContentHeight + Theme.Metrics.margin)
                ForEach(used..<rows, id: \.self) { row in
                    ForEach(0..<Theme.Metrics.homeColumns, id: \.self) { column in
                        let frame = HomeGridSpec.frame(
                            of: GridRect(origin: GridCell(column: column, row: row), size: GridSize(1, 1)))
                        RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                            )
                            .frame(width: frame.width, height: frame.height)
                            .offset(
                                x: ScreenGeometry.topFlare + Theme.Metrics.margin + frame.minX,
                                y: headerHeight + frame.minY)
                    }
                }
                Text("Room for \(left) more row\(left == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: Theme.Metrics.expandedWidth)
                    .offset(y: headerHeight + Theme.Metrics.homeMaxContentHeight + 2)
            }
            .frame(width: Theme.Metrics.expandedWidth, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: While dragging

/// The widget being dragged, lifted, under the pointer at 1:1. It is drawn over everything in the pane, so it can cross from
/// Add Widgets into the preview.
struct HomeDragLayer: View {
    let editor: HomeEditor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let gesture = editor.gesture, let placement = editor.dragging, let point = editor.dragPoint,
            let model = editor.previewModel
        {
            let grab: CGSize = {
                switch gesture {
                case .move(_, let grab), .add(_, let grab): grab
                case .resize: .zero
                }
            }()
            let width = HomeGridSpec.width(columns: placement.size.columns)
            let height = HomeGridSpec.height(rows: placement.size.rows)
            HomeWidgetView(placement: placement, size: placement.size, viewModel: model.viewModel)
                .frame(width: width, height: height)
                .scaleEffect(reduceMotion ? 1 : Theme.Motion.liftScale)
                .shadow(color: .black.opacity(reduceMotion ? 0 : 0.35), radius: 14, y: 8)
                .position(x: point.x - grab.width + width / 2, y: point.y - grab.height + height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: The hint under the preview

/// What the editor says under the preview: what letting go does while dragging, why an edit was refused, what a removal did (with
/// Undo), or how to use it, then what room is left.
struct HomeEditorHint: View {
    let editor: HomeEditor

    static let idle = "Drag to move \u{00B7} drag a corner to resize \u{00B7} the minus button removes one"

    var body: some View {
        let catalog = editor.settings.widgetDescriptor(for:)
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                if let message = editor.message {
                    Label(message, systemImage: "hand.point.up.left")
                        .foregroundStyle(Color.accentColor)
                } else if let refusal = editor.refusal {
                    Label(refusal, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                } else if let notice = editor.notice {
                    Text(notice)
                    Button("Undo") { editor.undoManager?.undo() }
                        .buttonStyle(.link)
                } else {
                    Label(Self.idle, systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
            }
            Text(Self.capacity(editor.displayLayout, catalog: catalog))
        }
    }

    /// Room left, in words; a full Home says what to do.
    static func capacity(_ layout: HomeLayout, catalog: HomeLayout.Catalog) -> String {
        let text = layout.capacityText(catalog: catalog)
        return text == "Home is full" ? "Home is full. Make a widget smaller or remove one to add another." : text
    }
}
