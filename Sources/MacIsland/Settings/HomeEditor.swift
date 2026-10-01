import AppKit
import SwiftUI

/// What is being dragged in the Home editor.
enum HomeGesture: Equatable {
    /// A widget on Home, picked up `grab` from its top left.
    case move(WidgetPlacement, grab: CGSize)
    /// A widget from Add Widgets, held by the middle of the size it would land at.
    case add(WidgetPlacement, grab: CGSize)
    /// A widget's resize handle, from the size it had.
    case resize(UUID, from: GridSize)
}

/// What a key does in the editor, apart from which key it is.
enum HomeKey: Equatable {
    case delete
    /// Selects the next widget that way.
    case select(HomeMove)
    case move(HomeMove)
    case nextSize, previousSize
    case escape
}

/// What the Home editor does to the layout. It owns the selection, the gestures (move, add, resize), the live preview while
/// one is going, and undo; the rules themselves (what fits) are `HomeLayout`'s and the grid maths are `HomeGridSpec`'s.
/// Every edit is `settings.setHomeLayout`, so the real island changes at once.
///
/// The gestures are plain drags in one coordinate space (`HomeEditor.space`), not system drag and drop: the target is worked out
/// from the pointer (`gridFrame` and `bandFrame`, which the views publish), so it can't flicker between spots, and the same
/// code handles moving, adding, and dragging off to remove. Nothing is saved until the drag ends, and that is one undo step.
@MainActor
@Observable
final class HomeEditor {
    /// The named coordinate space the canvas and the pane share.
    nonisolated static let space = "MacIslandHomeEditor"

    let settings: AppSettings

    var selection: UUID?
    /// The drag going on, if any.
    private(set) var gesture: HomeGesture?
    /// Where the pointer is, in `space`, while dragging.
    private(set) var dragPoint: CGPoint?
    /// While a drag is going, the layout as it would be if it ended here. Home shows this instead of the real layout, so the other
    /// widgets move out of the way, and nothing is saved until the drag ends. Nil when nothing is being previewed.
    private(set) var live: HomeLayout?
    /// While dragging: what letting go does ("Release to place Music."), or why it can't.
    private(set) var message: String?
    /// After a removal: what happened, with Undo beside it.
    private(set) var notice: String?
    /// Why the last edit was refused; cleared by the next one.
    private(set) var refusal: String?
    /// Where Home's grid and the preview band are in `space`; the views publish them.
    var gridFrame: CGRect = .zero
    var bandFrame: CGRect = .zero
    /// The island at its fullest (its outline with all the room to grow), in `space`. Letting go inside it places a widget; letting go
    /// outside it, on the wallpaper, puts the widget back where it was. Until the preview publishes it, the whole band counts.
    var islandFrame: CGRect = .zero
    @ObservationIgnored weak var undoManager: UndoManager?
    /// The preview Home is drawn in, which is told about `live` so its island can grow or shrink with the layout.
    @ObservationIgnored weak var previewModel: IslandPreviewModel?
    /// Whether the primary mouse button is down. A gesture that is going while it isn't is stale. Tests replace it.
    @ObservationIgnored var isMouseDown: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    /// Set by the Settings window: listens for the mouse coming up, so a drag whose view went away still ends.
    @ObservationIgnored var watchesMouseUp = false
    @ObservationIgnored private var releaseMonitor: Any?
    /// A tap on the trackpad's haptic engine for each new place or size. Tests replace it.
    @ObservationIgnored var snapHaptic: () -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private enum Target: Equatable {
        case place(Int)
        case outside
    }

    @ObservationIgnored private var target: Target?
    @ObservationIgnored private var canDrop = true
    @ObservationIgnored private var resizeOrigin = CGPoint.zero
    /// Where the handle was held, from the widget's bottom right, so the box follows the handle and not the pointer.
    @ObservationIgnored private var resizeGrab = CGSize.zero
    @ObservationIgnored private var resizeTarget: GridSize?

    init(settings: AppSettings) { self.settings = settings }

    var layout: HomeLayout { settings.homeLayout }

    /// What Home is showing: the preview while a drag is going, otherwise the real layout.
    var displayLayout: HomeLayout { live ?? layout }

    private var catalog: HomeLayout.Catalog { settings.widgetDescriptor(for:) }

    /// Where a widget can be placed: the island, or the band until the island's frame is known.
    var dropFrame: CGRect { islandFrame == .zero ? bandFrame : islandFrame }

    /// The widget being moved or added.
    var dragging: WidgetPlacement? {
        switch gesture {
        case .move(let placement, _), .add(let placement, _): placement
        default: nil
        }
    }

    private func title(of widget: WidgetID) -> String { settings.widgetDescriptor(for: widget)?.title ?? "Widget" }

    // MARK: Move and add

    /// A widget on Home was picked up at `point`.
    func beginMove(_ id: UUID, at point: CGPoint) {
        dropStaleGesture()
        guard gesture == nil, let index = layout.index(of: id), let rect = layout.frames(catalog: catalog)[id] else {
            return
        }
        let frame = HomeGridSpec.frame(of: rect)
        start(
            .move(
                layout.widgets[index],
                grab: CGSize(
                    width: point.x - (gridFrame.minX + frame.minX), height: point.y - (gridFrame.minY + frame.minY))),
            at: point)
        selection = id
        // It starts where it is: no tick for that.
        target = .place(index)
    }

    /// A widget from Add Widgets was picked up at `point`, to land at `size`.
    func beginAdd(_ widget: WidgetID, size: GridSize, at point: CGPoint) {
        dropStaleGesture()
        guard gesture == nil, !layout.isPlaced(widget), let descriptor = catalog(widget) else { return }
        var placement = layout.hidden.first { $0.widget == widget } ?? WidgetPlacement(widget: widget)
        placement.size = HomeLayout.repairedSize(size, for: descriptor)
        let grab = CGSize(
            width: HomeGridSpec.width(columns: placement.size.columns) / 2,
            height: HomeGridSpec.height(rows: placement.size.rows) / 2)
        start(.add(placement, grab: grab), at: point)
    }

    /// The size a widget is added at: the one it last had on Home, or its default.
    func addSize(for widget: WidgetID) -> GridSize {
        guard let descriptor = catalog(widget) else { return .unset }
        guard let last = layout.hidden.first(where: { $0.widget == widget })?.size, !last.isUnset else {
            return descriptor.defaultSize
        }
        return HomeLayout.repairedSize(last, for: descriptor)
    }

    private func start(_ new: HomeGesture, at point: CGPoint) {
        gesture = new
        watchForRelease()
        dragPoint = point
        refusal = nil
        notice = nil
        message = nil
        target = nil
        canDrop = true
    }

    /// The pointer moved. Inside the preview the widget lands at the cell nearest its top left, and the others move to
    /// make room; outside it, nothing is placed: a widget from Home goes back and one from Add Widgets is dropped.
    func update(to point: CGPoint) {
        guard let gesture else { return }
        dragPoint = point
        let placement: WidgetPlacement
        let grab: CGSize
        switch gesture {
        case .move(let moved, let held), .add(let moved, let held): (placement, grab) = (moved, held)
        case .resize: return
        }
        guard dropFrame.contains(point) else {
            retarget(.outside, placement)
            return
        }
        let topLeft = CGPoint(x: point.x - grab.width - gridFrame.minX, y: point.y - grab.height - gridFrame.minY)
        var others = layout
        others.widgets.removeAll { $0.id == placement.id }
        let cell = HomeGridSpec.cell(nearest: topLeft, size: layout.size(of: placement, catalog: catalog))
        retarget(
            .place(HomeGridSpec.insertionIndex(for: cell, among: others.rects(catalog: catalog))), placement)
    }

    private func retarget(_ new: Target, _ placement: WidgetPlacement) {
        guard new != target else { return }
        target = new
        snapHaptic()
        let name = title(of: placement.widget)
        switch new {
        case .place(let index):
            if let result = layout.inserting(placement, at: index, catalog: catalog) {
                canDrop = true
                message = "Release to place \(name)."
                setLive(result == layout ? nil : result)
            } else {
                canDrop = false
                message = "\(name) won\u{2019}t fit there. \(layout.capacityText(catalog: catalog))."
                setLive(nil)
            }
        case .outside:
            // Off the island, on the wallpaper: nothing lands, and the widget goes back where it was.
            canDrop = false
            message = nil
            setLive(nil)
        }
    }

    /// Lets go at `point`. What was shown is what is kept, as one undo step; a spot it won't fit snaps the widget back and
    /// says why. False when nothing changed.
    @discardableResult
    func end(at point: CGPoint) -> Bool {
        if case .resize? = gesture { return endResize() }
        guard let gesture, let placement = dragging else { return false }
        update(to: point)
        let isMove = if case .move = gesture { true } else { false }
        let landed = target
        let shown = live
        let allowed = canDrop
        let failure = message
        defer { finish() }
        switch landed {
        case .outside?:
            return false
        case .place?:
            guard allowed else {
                refusal = failure
                return false
            }
            guard let shown else { return false }
            selection = placement.id
            withAnimation(Theme.Motion.resize) {
                apply(shown, isMove ? "Move Widget" : "Add Widget")
            }
            return true
        case nil:
            return false
        }
    }

    /// Escape, or anything else that calls a drag off: nothing changes.
    func cancel() { finish() }

    /// A gesture that is going with the mouse up never heard it end (its view went away mid-drag): call it off before starting another.
    private func dropStaleGesture() {
        guard gesture != nil, !isMouseDown() else { return }
        cancel()
    }

    /// After the mouse comes up and SwiftUI has had its chance to end the drag, end it if nothing did. Where the pointer last was decides.
    private func watchForRelease() {
        guard watchesMouseUp, releaseMonitor == nil else { return }
        releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.endIfStuck() } }
            return event
        }
    }

    private func stopWatchingForRelease() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    /// Ends a drag that is still going after the mouse came up.
    func endIfStuck() {
        guard let gesture else { return }
        if case .resize = gesture {
            endResize()
        } else {
            end(at: dragPoint ?? .zero)
        }
    }

    private func finish() {
        gesture = nil
        stopWatchingForRelease()
        dragPoint = nil
        target = nil
        message = nil
        canDrop = true
        resizeTarget = nil
        setLive(nil)
    }

    /// Changes the preview, with the widgets sliding to their new places. The island around them follows.
    private func setLive(_ new: HomeLayout?) {
        guard new != live else { return }
        withAnimation(Theme.Motion.resize) {
            live = new
            previewModel?.viewModel.homeLayoutOverride = new
        }
    }

    // MARK: Resize

    /// A widget's resize handle was picked up, at `point` when it is known.
    func beginResize(_ id: UUID, at point: CGPoint? = nil) {
        dropStaleGesture()
        guard gesture == nil, let index = layout.index(of: id), let rect = layout.frames(catalog: catalog)[id] else {
            return
        }
        let frame = HomeGridSpec.frame(of: rect)
        gesture = .resize(id, from: layout.widgets[index].size)
        watchForRelease()
        resizeOrigin = CGPoint(x: gridFrame.minX + frame.minX, y: gridFrame.minY + frame.minY)
        resizeGrab =
            point.map {
                CGSize(width: $0.x - resizeOrigin.x - frame.width, height: $0.y - resizeOrigin.y - frame.height)
            } ?? .zero
        resizeTarget = layout.widgets[index].size
        selection = id
        refusal = nil
        notice = nil
        message = nil
    }

    /// The handle moved: the widget takes the size nearest the box the pointer has drawn, among those that fit. A size that
    /// is nearer but won't fit says so.
    func updateResize(to point: CGPoint) {
        guard case .resize(let id, _)? = gesture, let index = layout.index(of: id),
            let descriptor = catalog(layout.widgets[index].widget)
        else { return }
        dragPoint = point
        let extent = CGSize(
            width: point.x - resizeOrigin.x - resizeGrab.width, height: point.y - resizeOrigin.y - resizeGrab.height)
        let fitting = descriptor.sizes.filter { layout.resizing(id, to: $0, catalog: catalog) != nil }
        let wanted = HomeGridSpec.nearest(to: extent, among: descriptor.sizes)
        let chosen = HomeGridSpec.nearest(to: extent, among: fitting.isEmpty ? [layout.widgets[index].size] : fitting)
        message = wanted == chosen ? chosen.displayName : "\(wanted.displayName) won\u{2019}t fit"
        guard chosen != resizeTarget else { return }
        resizeTarget = chosen
        snapHaptic()
        setLive(chosen == layout.widgets[index].size ? nil : layout.resizing(id, to: chosen, catalog: catalog))
    }

    @discardableResult
    func endResize() -> Bool {
        guard case .resize? = gesture else { return false }
        let shown = live
        defer { finish() }
        guard let shown else { return false }
        withAnimation(Theme.Motion.resize) { apply(shown, "Resize Widget") }
        return true
    }

    // MARK: Commands (every one is one undo step)

    func remove(_ id: UUID) {
        let new = layout.removing(id)
        guard new != layout else {
            refusal = "Home keeps at least one widget."
            return
        }
        let name = layout.placement(id: id).map { title(of: $0.widget) } ?? "Widget"
        apply(new, "Remove Widget")
        notice = "Removed \(name)."
        if selection == id { selection = nil }
    }

    func move(_ id: UUID, _ move: HomeMove) {
        guard let new = layout.moving(id, move, catalog: catalog) else {
            refusal = "That won\u{2019}t fit. \(layout.capacityText(catalog: catalog))."
            return
        }
        apply(new, "Move Widget")
    }

    /// Adds a widget at its last size, or its default, where it fits (clicking a tile's plus).
    func add(_ widget: WidgetID, size: GridSize? = nil) {
        guard let new = layout.adding(widget, size: size, catalog: catalog) else {
            refusal = "There is no room for that. \(layout.capacityText(catalog: catalog))."
            return
        }
        apply(new, "Add Widget")
        selection = new.widgets.first { $0.widget == widget }?.id
    }

    /// Gives a widget another of its sizes, if everything still fits.
    func setSize(_ size: GridSize, for id: UUID) {
        guard let new = layout.resizing(id, to: size, catalog: catalog) else {
            refusal = "\(size.displayName) won\u{2019}t fit. \(layout.capacityText(catalog: catalog))."
            return
        }
        apply(new, "Resize Widget")
    }

    /// The next (or previous) size in the order the widget lists them: Make Larger and Make Smaller.
    func stepSize(_ id: UUID, by delta: Int) {
        guard let placement = layout.placement(id: id), layout.index(of: id) != nil,
            let sizes = catalog(placement.widget)?.sizes, let current = sizes.firstIndex(of: placement.size),
            sizes.indices.contains(current + delta)
        else {
            refusal = "That is already the \(delta > 0 ? "largest" : "smallest") size."
            return
        }
        setSize(sizes[current + delta], for: id)
    }

    func setOptions(_ options: WidgetOptions, for id: UUID) {
        apply(layout.setting(options, for: id), "Change Widget")
    }

    func applyPreset(_ preset: HomePreset) {
        apply(layout.applying(preset.layout, catalog: catalog), "Use \(preset.name)")
    }

    func reset() { applyPreset(HomeLayout.presets[0]) }

    // MARK: Saved layouts

    /// Keeps the arrangement on Home under a name, for the Presets menu.
    @discardableResult
    func saveLayout(named name: String) -> SavedHomePreset.SaveResult {
        refusal = nil
        notice = nil
        return settings.saveHomePreset(named: name)
    }

    /// A saved layout in place of Home, with the options it was saved with.
    func applySaved(_ saved: SavedHomePreset) {
        apply(layout.applying(saved.layout, usesPresetOptions: true, catalog: catalog), "Use \(saved.name)")
    }

    /// Removes a saved layout; undo brings it back where it was.
    func deleteSaved(_ id: UUID) {
        guard let removed = settings.deleteHomePreset(id) else { return }
        undoManager?.registerUndo(withTarget: self) { $0.restoreSaved(removed.preset, at: removed.index) }
        undoManager?.setActionName("Delete Saved Layout")
    }

    private func restoreSaved(_ preset: SavedHomePreset, at index: Int) {
        settings.restoreHomePreset(preset, at: index)
        undoManager?.registerUndo(withTarget: self) { $0.deleteSaved(preset.id) }
        undoManager?.setActionName("Delete Saved Layout")
    }

    func replace(with new: HomeLayout, actionName: String) { apply(new, actionName) }

    // MARK: Keys

    /// A key in the editor. True when it did something (or was the editor's to take).
    @discardableResult
    func perform(_ key: HomeKey) -> Bool {
        switch key {
        case .escape:
            guard gesture != nil else { return false }
            cancel()
            return true
        case .delete:
            guard let selection, layout.index(of: selection) != nil else { return false }
            remove(selection)
            return true
        case .select(let direction):
            guard let next = neighbor(of: selection, direction) else { return false }
            selection = next
            return true
        case .move(let direction):
            guard let selection, layout.index(of: selection) != nil else { return false }
            move(selection, direction)
            return true
        case .nextSize, .previousSize:
            guard let selection, layout.index(of: selection) != nil else { return false }
            stepSize(selection, by: key == .nextSize ? 1 : -1)
            return true
        }
    }

    /// The widget next to `id` in a direction: the one before or after it in reading order, or the nearest one above or below.
    /// With nothing selected, the first.
    private func neighbor(of id: UUID?, _ direction: HomeMove) -> UUID? {
        let widgets = layout.widgets
        guard let id, let index = layout.index(of: id) else { return widgets.first?.id }
        switch direction {
        case .left: return index > 0 ? widgets[index - 1].id : nil
        case .right: return index < widgets.count - 1 ? widgets[index + 1].id : nil
        case .up, .down:
            let frames = layout.frames(catalog: catalog)
            guard let here = frames[id] else { return nil }
            let candidates = widgets.compactMap { placement -> (UUID, Int, Int)? in
                guard placement.id != id, let rect = frames[placement.id] else { return nil }
                let rows =
                    direction == .up ? here.origin.row - rect.endRow : rect.origin.row - here.endRow
                guard rows >= 0 else { return nil }
                let first = rect.origin.column
                let last = first + rect.size.columns - 1
                let column = here.origin.column
                return (placement.id, rows, column < first ? first - column : (column > last ? column - last : 0))
            }
            return candidates.min { ($0.1, $0.2) < ($1.1, $1.2) }?.0
        }
    }

    // MARK: Undo

    private func apply(_ new: HomeLayout, _ actionName: String) {
        refusal = nil
        notice = nil
        let old = settings.homeLayout
        settings.setHomeLayout(new)
        guard settings.homeLayout != old else { return }
        undoManager?.registerUndo(withTarget: self) { editor in
            editor.apply(old, actionName)
        }
        undoManager?.setActionName(actionName)
    }
}

private struct HomeEditorKey: EnvironmentKey {
    static let defaultValue: HomeEditor? = nil
}

extension EnvironmentValues {
    /// Set only in the Settings editor: Home's widgets draw their editing chrome while it is.
    var homeEditor: HomeEditor? {
        get { self[HomeEditorKey.self] }
        set { self[HomeEditorKey.self] = newValue }
    }
}
