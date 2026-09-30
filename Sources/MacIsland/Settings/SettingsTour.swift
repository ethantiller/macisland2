import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

// The Settings tour: a black callout with an arrow points at a real control, with a ring in the system accent color around it.
// It is Settings chrome (like the Home editor's badges and rings), drawn over the window and never on the island. Nothing is
// dimmed: a scrim with a cutout would hide the preview the tour is about.

// MARK: Stops

/// What a stop points at. Each is anchored at one view with `.tourAnchor(_:)`.
enum TourTarget: Hashable {
    case search, previewBand, shortcut, peekOnHover, notShownTray, menuBarRow, addWidgets, calendarEvents, dragTarget,
        musicCompact, pomodoro, toolsRow, quietInFocus, accessList, guide
    /// The visible part of the pane's scrolling form: a target outside it has been scrolled out of view.
    case paneViewport

    /// Whether the target sits in the pane's scrolling form, and so can be scrolled out of view. The search field, the preview,
    /// and the tab tray don't scroll.
    var scrollsWithPane: Bool {
        switch self {
        case .search, .previewBand, .notShownTray, .paneViewport: false
        default: true
        }
    }
}

struct TourStop: Identifiable, Equatable {
    /// Which side of the target the callout prefers. The placement function flips it when there isn't room.
    enum Placement: Equatable { case above, below, leading, trailing }

    let id: String
    /// The tour version that added it. A re-run for someone who saw version n shows the stops with a newer `since`.
    let since: Int
    let pane: SettingsPane
    let target: TourTarget
    let placement: Placement
    /// The `SettingsAnchor` the pane scrolls to (its top) when the stop starts.
    let scrollAnchor: String?
    /// What the stop shows in the preview, restored to the pane's own context when the stop ends.
    let preview: PreviewContext?
    let title: String
    let copy: String

    /// Every pane has at least one stop, and each pane's stops are consecutive except General, which opens and closes the tour.
    static let all: [TourStop] = [
        TourStop(
            id: "search", since: 1, pane: .general, target: .search, placement: .trailing, scrollAnchor: nil,
            preview: nil, title: "Find Any Setting",
            copy:
                "Search by name, or by another word for it, like \u{201C}airpods\u{201D}. \u{2318}F works from anywhere in this window."
        ),
        TourStop(
            id: "preview", since: 1, pane: .general, target: .previewBand, placement: .below, scrollAnchor: nil,
            preview: nil, title: "Your Island, Live",
            copy:
                "Each pane shows the real island from sample data, so a change appears where it lands. Swipe on it, or use the arrows, to see Compact, Peek, Banner, and Expanded."
        ),
        TourStop(
            id: "shortcut", since: 1, pane: .general, target: .shortcut, placement: .below,
            scrollAnchor: SettingsAnchor.shortcut, preview: nil, title: "Open It From Anywhere",
            copy: "Click here and press the keys you want to open the island from anywhere."),
        TourStop(
            id: "input", since: 1, pane: .general, target: .peekOnHover, placement: .below,
            scrollAnchor: SettingsAnchor.input, preview: nil, title: "Hover and Swipe",
            copy:
                "If the island opens when you reach for the menu bar, turn off Peek on Hover; a click still opens it. Swiping can be turned off here too."
        ),
        TourStop(
            id: "tabs", since: 1, pane: .tabs, target: .notShownTray, placement: .below, scrollAnchor: nil,
            preview: nil, title: "Arrange Your Tabs",
            copy:
                "Drag a tab onto another to swap them, or drag one from Not Shown to replace a tab. Five fit left of the notch and one right of it."
        ),
        TourStop(
            id: "menuBar", since: 1, pane: .tabs, target: .menuBarRow, placement: .above,
            scrollAnchor: SettingsAnchor.menuBar, preview: PreviewContext(presentation: .menuBar, menuBarTab: .home),
            title: "Put a Module in the Menu Bar",
            copy: "Switch a module on to give it its own icon. Drag its window\u{2019}s header away to pop it out."),
        TourStop(
            id: "homeCanvas", since: 1, pane: .home, target: .previewBand, placement: .below, scrollAnchor: nil,
            preview: nil, title: "Arrange Home",
            copy:
                "Drag a widget to move it, or drag its corner to resize it. The island grows and shrinks with its rows."
        ),
        TourStop(
            id: "addWidgets", since: 1, pane: .home, target: .addWidgets, placement: .above,
            scrollAnchor: SettingsAnchor.widgets, preview: nil, title: "Add Widgets",
            copy: "Everything not on Home waits here. Drag a widget into the island, or press its plus."),
        TourStop(
            id: "upNext", since: 1, pane: .home, target: .calendarEvents, placement: .above,
            scrollAnchor: SettingsAnchor.upNext, preview: nil, title: "Up Next",
            copy:
                "Turn these on to see your next meeting and due reminders on Home, with a banner before they start."),
        TourStop(
            id: "dragTarget", since: 1, pane: .shelf, target: .dragTarget, placement: .below,
            scrollAnchor: SettingsAnchor.files, preview: nil, title: "When You Drag a File",
            copy:
                "Choose what the island becomes as a file comes near: the Shelf, AirDrop, both, or nothing."),
        TourStop(
            id: "music", since: 1, pane: .media, target: .musicCompact, placement: .below,
            scrollAnchor: SettingsAnchor.music, preview: nil, title: "Music Beside the Notch",
            copy: "Turn this off to keep music in Home and the Media tab only."),
        TourStop(
            id: "pomodoro", since: 2, pane: .clock, target: .pomodoro, placement: .below,
            scrollAnchor: SettingsAnchor.pomodoro, preview: nil, title: "Set Your Pomodoro",
            copy:
                "Choose how long a focus session and each break last, and how many sessions come before the long break."
        ),
        TourStop(
            id: "toolsRow", since: 1, pane: .tools, target: .toolsRow, placement: .below,
            scrollAnchor: SettingsAnchor.toolsRow, preview: nil, title: "Your Tools Row",
            copy:
                "Choose how many tools the row shows, then drag them into order below. Home\u{2019}s quick tools are the first four."
        ),
        TourStop(
            id: "interruptions", since: 1, pane: .notifications, target: .quietInFocus, placement: .below,
            scrollAnchor: SettingsAnchor.interruptions, preview: nil, title: "Choose What Interrupts You",
            copy:
                "Click an interruption to see its banner above, and switch off any you don\u{2019}t want. Quiet in Focus holds them while a Focus is on."
        ),
        TourStop(
            id: "privacy", since: 1, pane: .privacy, target: .accessList, placement: .above,
            scrollAnchor: SettingsAnchor.access, preview: nil, title: "Privacy in One Place",
            copy:
                "Everything MacIsland sends, runs, and may use is listed here, and each can be turned off."),
        TourStop(
            id: "guide", since: 1, pane: .general, target: .guide, placement: .above,
            scrollAnchor: SettingsAnchor.guide, preview: nil, title: "See This Again",
            copy: "Replay the welcome guide or this tour here anytime."),
    ]
}

// MARK: Running

/// Where the tour is. Pure state: the window starts it, moves the pane for each stop, and records it when it ends.
@MainActor
@Observable
final class SettingsTour {
    let stops: [TourStop]
    /// The stop the tour is on. Nil: not running.
    private(set) var index: Int?

    @ObservationIgnored private let onFinish: @MainActor () -> Void

    init(stops: [TourStop] = TourStop.all, onFinish: @escaping @MainActor () -> Void) {
        self.stops = stops
        self.onFinish = onFinish
    }

    var current: TourStop? { index.map { stops[$0] } }
    var isRunning: Bool { index != nil }

    func start() {
        index = stops.isEmpty ? nil : 0
    }

    /// The next stop, or the end after the last.
    func next() {
        guard let index else { return }
        if index + 1 < stops.count { self.index = index + 1 } else { end() }
    }

    func back() {
        guard let index, index > 0 else { return }
        self.index = index - 1
    }

    /// The person chose a pane in the sidebar: the tour follows them to that pane's first stop, instead of fighting them. Does
    /// nothing while the tour is already on that pane (it moves the pane itself for each stop).
    func jump(to pane: SettingsPane) {
        guard isRunning, current?.pane != pane, let first = stops.firstIndex(where: { $0.pane == pane }) else { return }
        index = first
    }

    /// Done, End Tour, or the window closing.
    func end() {
        guard isRunning else { return }
        index = nil
        onFinish()
    }
}

// MARK: Anchors

/// Where each target is, in the window's own coordinates. Fed by `.tourAnchor(_:)` through `onGeometryChange`, the way the Home
/// editor learns where its band and grid are.
@MainActor
@Observable
final class TourAnchors {
    nonisolated static let space = "SettingsTour"

    private(set) var frames: [TourTarget: CGRect] = [:]

    /// Does nothing unless the frame changes, so a view reporting the same frame again can't start an update loop.
    func set(_ target: TourTarget, _ frame: CGRect?) {
        guard frames[target] != frame else { return }
        frames[target] = frame
    }
}

private struct TourAnchorsKey: EnvironmentKey {
    static let defaultValue: TourAnchors? = nil
}

extension EnvironmentValues {
    var tourAnchors: TourAnchors? {
        get { self[TourAnchorsKey.self] }
        set { self[TourAnchorsKey.self] = newValue }
    }
}

private struct TourAnchorModifier: ViewModifier {
    let target: TourTarget?
    @Environment(\.tourAnchors) private var anchors

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(TourAnchors.space))
            } action: {
                if let target { anchors?.set(target, $0) }
            }
            // A pane that is gone never leaves a stale frame behind.
            .onDisappear { if let target { anchors?.set(target, nil) } }
    }
}

extension View {
    /// Tells the Settings tour where this view is. Free when no tour is in the environment. Nil anchors nothing, so a view built in
    /// a `ForEach` can anchor just its first element.
    func tourAnchor(_ target: TourTarget?) -> some View {
        modifier(TourAnchorModifier(target: target))
    }
}

// MARK: Placement

/// Where the callout goes: on the preferred side of the target if it fits, else the opposite, else a side, else the side with the
/// most room; centered on the target, kept inside the window; with its arrow on the target's center. Pure, so it is tested.
struct CalloutPlacement: Equatable {
    /// The callout, in the tour's space.
    var frame: CGRect
    /// The side of the target it ended up on.
    var placement: TourStop.Placement
    /// Along the callout's edge that faces the target, from that edge's leading or top end, to the arrow's center.
    var arrowOffset: CGFloat

    /// `gap` is the distance from the target to the arrow's tip.
    static func place(
        target: CGRect, size: CGSize, in bounds: CGRect, preferred: TourStop.Placement, gap: CGFloat, arrow: CGSize,
        edgeInset: CGFloat, cornerRadius: CGFloat
    ) -> CalloutPlacement {
        let inner = bounds.insetBy(dx: edgeInset, dy: edgeInset)
        let offset = gap + arrow.height

        func room(_ side: TourStop.Placement) -> CGFloat {
            switch side {
            case .below: inner.maxY - target.maxY - offset
            case .above: target.minY - offset - inner.minY
            case .trailing: inner.maxX - target.maxX - offset
            case .leading: target.minX - offset - inner.minX
            }
        }
        func needed(_ side: TourStop.Placement) -> CGFloat {
            side == .above || side == .below ? size.height : size.width
        }

        let opposite: TourStop.Placement =
            switch preferred {
            case .above: .below
            case .below: .above
            case .leading: .trailing
            case .trailing: .leading
            }
        let across: [TourStop.Placement] = preferred == .above || preferred == .below ? [.leading, .trailing] : [.above, .below]
        let order = [preferred, opposite] + across
        let side =
            order.first(where: { room($0) >= needed($0) }) ?? order.max(by: { room($0) < room($1) }) ?? preferred

        var origin: CGPoint
        switch side {
        case .below: origin = CGPoint(x: target.midX - size.width / 2, y: target.maxY + offset)
        case .above: origin = CGPoint(x: target.midX - size.width / 2, y: target.minY - offset - size.height)
        case .trailing: origin = CGPoint(x: target.maxX + offset, y: target.midY - size.height / 2)
        case .leading: origin = CGPoint(x: target.minX - offset - size.width, y: target.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, inner.minX), max(inner.maxX - size.width, inner.minX))
        origin.y = min(max(origin.y, inner.minY), max(inner.maxY - size.height, inner.minY))
        let frame = CGRect(origin: origin, size: size)

        // The arrow points at the target's center and never sits on a rounded corner.
        let horizontal = side == .above || side == .below
        let length = horizontal ? frame.width : frame.height
        let wanted = horizontal ? target.midX - frame.minX : target.midY - frame.minY
        let lowest = cornerRadius + arrow.width / 2
        let highest = max(length - cornerRadius - arrow.width / 2, lowest)
        return CalloutPlacement(frame: frame, placement: side, arrowOffset: min(max(wanted, lowest), highest))
    }

    /// Whether a target is on screen in the pane: its center is inside the pane's visible part. Targets outside the scrolling form
    /// always are.
    static func isVisible(_ frame: CGRect, in viewport: CGRect?) -> Bool {
        guard let viewport else { return true }
        return viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}

/// How a stop is shown, given where its target is.
enum TourVisibility: Equatable {
    /// The ring is on the target and the callout's arrow points at it.
    case pointing(CGRect)
    /// The target is scrolled out of view or hidden (the sidebar, for the search field): the callout sits at the bottom of the pane
    /// with no arrow and no ring.
    case docked
    /// The target hasn't reported a frame yet (its pane is still appearing): nothing is drawn for the stop.
    case hidden

    static func resolve(_ target: TourTarget, frames: [TourTarget: CGRect], unavailable: Set<TourTarget>) -> TourVisibility
    {
        if unavailable.contains(target) { return .docked }
        guard let frame = frames[target] else { return .hidden }
        if target.scrollsWithPane, !CalloutPlacement.isVisible(frame, in: frames[.paneViewport]) { return .docked }
        return .pointing(frame)
    }
}

// MARK: Drawing

/// The callout's arrow: a filled triangle with its tip toward the target.
struct TourArrow: Shape {
    /// The side of the target the callout is on. The tip points back at it.
    let side: TourStop.Placement

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch side {
        case .below:  // The callout is under the target: the tip points up.
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .above:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .trailing:  // The callout is right of the target: the tip points left.
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .leading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// The words of a stop on a black card, like the island: MacIsland is speaking, so it reads the same in a light or a dark window.
struct TourCallout: View {
    let stop: TourStop
    let index: Int
    let count: Int
    /// Set when the target is out of view: a Show Me button scrolls it back.
    var onShowMe: (() -> Void)?
    let onBack: () -> Void
    let onNext: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.rowSpacing) {
            HStack(alignment: .center, spacing: Theme.Metrics.rowSpacing) {
                Text(stop.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                IconButton(systemName: "xmark", label: "End Tour", size: 12, action: onEnd)
            }
            Text(stop.copy)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Metrics.rowSpacing) {
                Text("\(index + 1) of \(count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                Spacer(minLength: 0)
                if let onShowMe { ChipButton(title: "Show Me", action: onShowMe) }
                if index > 0 { ChipButton(title: "Back", action: onBack) }
                ChipButton(title: index + 1 == count ? "Done" : "Next", isProminent: true, action: onNext)
            }
        }
        .padding(Theme.Metrics.floatPadding)
        .frame(width: Theme.Metrics.tourCalloutWidth)
        .background(Theme.Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.Palette.widgetEdge, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
    }
}

/// The ring around the control a stop points at.
struct TourRing: View {
    let frame: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: Theme.Metrics.tourRingWidth)
            .frame(
                width: frame.width + 2 * Theme.Metrics.tourRingInset,
                height: frame.height + 2 * Theme.Metrics.tourRingInset
            )
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The tour over the whole window: the ring and the callout for the current stop. Only the callout takes clicks, so the control
/// being pointed at can be tried. It is an overlay on the window's content, so it is above the sidebar, the preview, and the pane.
struct SettingsTourOverlay: View {
    let tour: SettingsTour
    let anchors: TourAnchors
    /// Targets that can't be pointed at right now (the search field while the sidebar is hidden).
    var unavailable: Set<TourTarget> = []
    /// Scrolls the current stop's target back into view.
    let onShowMe: () -> Void

    @State private var calloutSize = CGSize(width: Theme.Metrics.tourCalloutWidth, height: 0)

    var body: some View {
        GeometryReader { geometry in
            if let stop = tour.current, let index = tour.index {
                let bounds = CGRect(origin: .zero, size: geometry.size)
                switch TourVisibility.resolve(stop.target, frames: anchors.frames, unavailable: unavailable) {
                case .hidden:
                    EmptyView()
                case .pointing(let target):
                    let placed = CalloutPlacement.place(
                        target: target, size: calloutSize, in: bounds, preferred: stop.placement,
                        gap: Theme.Metrics.tourRingInset + Theme.Metrics.tourGap, arrow: Theme.Metrics.tourArrow,
                        edgeInset: Theme.Metrics.tourEdgeInset, cornerRadius: Theme.Metrics.cardRadius)
                    ZStack(alignment: .topLeading) {
                        TourRing(frame: target)
                        TourArrowView(placed: placed)
                        callout(stop: stop, index: index, showsShowMe: false)
                            .offset(placed.frame.origin.asOffset)
                    }
                    .animation(Theme.Motion.resize, value: tour.index)
                    .transition(Theme.Motion.floatTransition)
                case .docked:
                    ZStack(alignment: .topLeading) {
                        callout(stop: stop, index: index, showsShowMe: true)
                            .offset(dockedOrigin(in: bounds))
                    }
                    .animation(Theme.Motion.resize, value: tour.index)
                    .transition(Theme.Motion.floatTransition)
                }
            }
        }
        .animation(Theme.Motion.float, value: tour.isRunning)
    }

    private func callout(stop: TourStop, index: Int, showsShowMe: Bool) -> some View {
        TourCallout(
            stop: stop, index: index, count: tour.stops.count, onShowMe: showsShowMe ? onShowMe : nil,
            onBack: { tour.back() }, onNext: { tour.next() }, onEnd: { tour.end() }
        )
        // The callout's height comes from its content, which the placement needs.
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            if calloutSize != $0 { calloutSize = $0 }
        }
    }

    /// Out of view: at the bottom center of the pane's visible part, with no arrow.
    private func dockedOrigin(in bounds: CGRect) -> CGSize {
        let viewport = anchors.frames[.paneViewport] ?? bounds
        return CGSize(
            width: viewport.midX - Theme.Metrics.tourCalloutWidth / 2,
            height: viewport.maxY - Theme.Metrics.tourEdgeInset - calloutSize.height)
    }
}

/// The arrow, on the callout's edge that faces the target, placed in the tour's space. It reaches 1 pt into the callout to cover the
/// hairline, so there is no seam.
struct TourArrowView: View {
    let placed: CalloutPlacement

    /// Where the arrow sits: its base on the callout's edge, its tip toward the target.
    private var rect: CGRect {
        let size = Theme.Metrics.tourArrow
        let frame = placed.frame
        let overlap: CGFloat = 1
        switch placed.placement {
        case .below:
            return CGRect(
                x: frame.minX + placed.arrowOffset - size.width / 2, y: frame.minY - size.height,
                width: size.width, height: size.height + overlap)
        case .above:
            return CGRect(
                x: frame.minX + placed.arrowOffset - size.width / 2, y: frame.maxY - overlap,
                width: size.width, height: size.height + overlap)
        case .trailing:
            return CGRect(
                x: frame.minX - size.height, y: frame.minY + placed.arrowOffset - size.width / 2,
                width: size.height + overlap, height: size.width)
        case .leading:
            return CGRect(
                x: frame.maxX - overlap, y: frame.minY + placed.arrowOffset - size.width / 2,
                width: size.height + overlap, height: size.width)
        }
    }

    var body: some View {
        TourArrow(side: placed.placement)
            .fill(Theme.Palette.surface)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension CGPoint {
    var asOffset: CGSize { CGSize(width: x, height: y) }
}

// MARK: Keys

/// Return is Next while the tour runs: a local key monitor, because a default button would take Return from the search field and
/// the weather field. It lets the key through while text is being edited or a shortcut is being recorded. Esc is not bound: in this
/// window it already clears search, cancels the recorder, and calls off a Home drag.
@MainActor
final class TourKeyMonitor {
    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    func start(in window: @escaping () -> NSWindow?, _ next: @escaping () -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_ANSI_KeypadEnter
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            let consumed = MainActor.assumeIsolated {
                guard isReturn, plain, let target = window(), event.window === target,
                    !(target.firstResponder is NSTextView), !ShortcutCapture.isActive
                else { return false }
                next()
                return true
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stop() }
}
