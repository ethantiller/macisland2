import AppKit
import SwiftUI

/// How large the island in the preview is.
enum PreviewPresentation: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case peek = "Peek"
    case banner = "Banner"
    case expanded = "Expanded"
    /// The menu bar, with an icon for each module you gave one. Only offered on the Tabs pane.
    case menuBar = "Menu Bar"

    var id: Self { self }
}

/// What the preview shows: a presentation and, when expanded, a tab.
struct PreviewContext: Equatable {
    var presentation: PreviewPresentation = .compact
    var tab: IslandModule = .home
    /// The module whose window the Menu Bar view shows, whether or not it has an icon there yet.
    var menuBarTab: IslandModule = .home
    /// The ambient event whose banner or alert the Banner presentation shows.
    var event: AmbientEvent?
    /// The volume HUD's alert, as the compact island shows it.
    var showsVolume = false
    /// A file is being dragged toward the island: the compact preview shows the drop target the setting chose.
    var fileDrag = false
    /// The mode the Clock tab opens on, for a pane that is about one of them. Nil leaves it as it was.
    var clockMode: ClockMode?
}

extension PreviewContext {
    /// What the preview shows for a module's options in Content: its tab, and for Clock the Pomodoro its options are about.
    static func options(for module: IslandModule) -> PreviewContext {
        PreviewContext(presentation: .expanded, tab: module, clockMode: module == .clock ? .pomodoro : nil)
    }
}

/// The island the Settings window draws beside its controls. It is the real `IslandView` over a second view
/// model built from sample data (`PreviewFeatures`), so it can't drift from the island, and it has its own
/// presentation and tab, so the real panel never opens or animates. It reads the live `AppSettings`, so a change
/// applies at once.
@MainActor
@Observable
final class IslandPreviewModel {
    let viewModel: IslandViewModel
    private(set) var context = PreviewContext()
    @ObservationIgnored private let scratch = PreviewFeatures.Scratch()

    init(live: IslandFeatures) {
        viewModel = IslandViewModel(features: PreviewFeatures.make(live: live, scratch: scratch))
        show(context, animated: false)
    }

    /// Stops what the sample features started and removes what they wrote.
    func stop() {
        viewModel.weather.stop()
        clearAnnouncements()
        scratch.remove()
    }

    private func clearAnnouncements() {
        viewModel.setFileDragActive(false)
        viewModel.dismissBanner()
        viewModel.clearAlert()
    }

    /// How far the preview has slid from the island (0) to the menu bar (1). It animates with the change of view, so the
    /// island shrinks and slides away, and the menu bar slides in and its window opens, in one continuous motion.
    private(set) var menuBarProgress = 0.0

    /// Shows a module's window in the Menu Bar view, keeping everything else about the preview as it was.
    func showMenuBar(_ module: IslandModule) {
        var next = context
        next.presentation = .menuBar
        next.menuBarTab = module
        show(next)
    }

    /// Whether Menu Bar is one of the views. It is on the Tabs pane, where the menu bar's icons are chosen, and nowhere else.
    var allowsMenuBar = false

    /// The views, in the picker's order.
    var presentations: [PreviewPresentation] {
        PreviewPresentation.allCases.filter { allowsMenuBar || $0 != .menuBar }
    }

    /// The presentation one step on (or back), in the picker's order. Nothing past either end.
    func step(_ delta: Int) {
        let all = presentations
        guard let index = all.firstIndex(of: context.presentation), all.indices.contains(index + delta) else { return }
        var next = context
        next.presentation = all[index + delta]
        show(next)
    }

    func canStep(_ delta: Int) -> Bool {
        let all = presentations
        guard let index = all.firstIndex(of: context.presentation) else { return false }
        return all.indices.contains(index + delta)
    }

    func show(_ context: PreviewContext, animated: Bool = true) {
        // Between Expanded and Menu Bar the views slide (the island out to the left, the menu bar in from the right, and back).
        let slides = context.presentation == .menuBar || self.context.presentation == .menuBar
        let apply = { [self] in
            self.context = context
            viewModel.resetPointerState()
            menuBarProgress = context.presentation == .menuBar ? 1 : 0
            switch context.presentation {
            case .compact:
                clearAnnouncements()
                viewModel.state = .compact
                viewModel.setFileDragActive(context.fileDrag)
            case .peek:
                clearAnnouncements()
                viewModel.state = .peek
            case .banner where context.showsVolume:
                clearAnnouncements()
                viewModel.state = .compact
                var alert = Announcements.volume(PreviewSamples.volume)
                alert.staysUntilSeen = true
                viewModel.flash(alert, respectingFocus: false)
            case .banner:
                clearAnnouncements()
                let announcement =
                    context.event.map {
                        Announcements.sample(for: $0, agenda: viewModel.agenda)
                    } ?? .banner(PreviewSamples.banner())
                switch announcement {
                case .banner(let banner):
                    viewModel.showBanner(banner, for: .seconds(86_400), respectingFocus: false)
                case .alert(var alert):
                    // An alert is drawn beside the notch, and stays for as long as it is looked at.
                    alert.staysUntilSeen = true
                    viewModel.state = .compact
                    viewModel.flash(alert, respectingFocus: false)
                }
            case .expanded:
                clearAnnouncements()
                viewModel.selectedTab = context.tab
                if let mode = context.clockMode { viewModel.clockMode = mode }
                viewModel.state = .expanded
            case .menuBar:
                // The island keeps the state it had: it shrinks and slides away as it is, and comes back the same.
                clearAnnouncements()
            }
        }
        if animated { withAnimation(slides ? Theme.Motion.slide : Theme.Motion.open, apply) } else { apply() }
    }
}

/// A band of desk with the island hung from its top edge at 1:1, and the presentations to choose from: the picker, arrow
/// buttons, or a two-finger swipe over the preview. Look-only: nothing inside the island takes a click, because the sample
/// features would otherwise act on the real Mac. The exceptions are the editors: on Home the widgets take drags, and on Tabs
/// the tab strip takes clicks and drags.
struct IslandPreview: View {
    let model: IslandPreviewModel
    /// While the Home editor is open the preview is its canvas: widgets take drags and clicks, and the rest of the
    /// island (the tab strip) still does not.
    var editor: HomeEditor?
    /// While the Tabs pane is open the tab strip is the canvas: click a tab to see it, drag one to move or swap it.
    var tabEditor: TabEditor?

    private var isEditingHome: Bool {
        editor != nil && model.context.presentation == .expanded && model.context.tab == .home
    }

    var body: some View {
        VStack(spacing: 10) {
            // Click a name to show that view, as the arrows and a swipe do.
            SettingsSegmented(
                options: model.presentations.map { DropdownOption($0, $0.rawValue) },
                selection: Binding(
                    get: { model.context.presentation },
                    set: {
                        var next = model.context
                        next.presentation = $0
                        model.show(next)
                    }
                ),
                accessibilityLabel: "Preview")

            PreviewBand(model: model, editor: editor, tabEditor: tabEditor)
                .tourAnchor(.previewBand)
                .overlay(alignment: .bottomLeading) { arrow(-1) }
                .overlay(alignment: .bottomTrailing) { arrow(1) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview of the island")

            if let tabEditor, model.context.presentation != .menuBar {
                NotShownTray(editor: tabEditor).tourAnchor(.notShownTray)
            }

            hints
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // The island's own gesture, over the preview: swipe left for the view before, right for the next.
        .background(
            PreviewSwipe { swipe in
                switch swipe {
                case .left: model.step(-1)
                case .right: model.step(1)
                default: break
                }
            })
    }

    /// A circled arrow in a corner of the preview: the view before, or the next.
    private func arrow(_ delta: Int) -> some View {
        Button {
            model.step(delta)
        } label: {
            Image(systemName: delta < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(model.canStep(delta) ? 1 : 0.35)
        .disabled(!model.canStep(delta))
        .padding(10)
        .accessibilityLabel(delta < 0 ? "Previous View" : "Next View")
    }

    /// What can be done here, so it is found: swiping, and dragging where the pane allows it.
    private var hints: some View {
        VStack(spacing: 3) {
            if let editor, isEditingHome {
                HomeEditorHint(editor: editor)
            } else {
                Label(
                    "Swipe left or right on the preview, or use the arrows, to change the view.",
                    systemImage: "hand.draw")
            }
            if model.context.presentation == .menuBar {
                Label(
                    "Click an icon, or a module below, to see its window. Turn one on to give it an icon.",
                    systemImage: "menubar.rectangle")
            } else if tabEditor != nil {
                Label(
                    tabEditor?.hint ?? TabEditor.idleHint,
                    systemImage: "arrow.left.arrow.right"
                )
                .foregroundStyle(tabEditor?.hint == nil ? Color.secondary : Color.accentColor)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

/// The band of desk with the island hung from its top edge at 1:1, and nothing else: no switcher, arrows, or hints. The Settings
/// preview puts those around it, and the first-run guide uses it alone as its stage. The island is the real `IslandView` over the
/// model's sample features; the Home and Tabs editors, when given, make their part of it take drags and clicks.
struct PreviewBand: View {
    private static let backgroundImage: NSImage? = {
        let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("MacIsland_MacIsland.bundle")
        let appResources = bundleURL.flatMap { Bundle(path: $0.path) }
        let bundle = appResources ?? Bundle.module
        guard let url = bundle.url(forResource: "macos-background", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    let model: IslandPreviewModel
    var editor: HomeEditor?
    var tabEditor: TabEditor?

    private var isEditingHome: Bool {
        editor != nil && model.context.presentation == .expanded && model.context.tab == .home
    }

    private var isEditingTabs: Bool { tabEditor != nil && model.context.presentation == .expanded }

    private var headerHeight: CGFloat {
        model.viewModel.geometry.notchSize.height + Theme.Metrics.contentTopGap
    }

    var body: some View {
        bandContent
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    if let backgroundImage = Self.backgroundImage {
                        Image(nsImage: backgroundImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        Color(white: 0.28)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
    }

    /// What fills the band: the island and the menu bar, side by side in one motion. Going to the menu bar the island shrinks and
    /// slides out to the left while the menu bar slides in from the right and its window opens; going back does the opposite.
    private var bandContent: some View {
        BandSlide(
            progress: model.menuBarProgress,
            island: { islandBand },
            menu: { reveal in
                MenuBarPreview(model: model, reveal: reveal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Metrics.previewBandHeight)
        .clipped()
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(HomeEditor.space))
        } action: {
            editor?.bandFrame = $0
        }
    }

    private var islandBand: some View {
        ZStack(alignment: .top) {
            if isEditingHome, let editor {
                // The island at its fullest: where a widget can be placed. Off it, on the wallpaper, a dragged widget goes back.
                Color.clear
                    .frame(
                        width: Theme.Metrics.expandedWidth,
                        height: headerHeight + Theme.Metrics.homeMaxContentHeight + Theme.Metrics.margin
                    )
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(HomeEditor.space))
                    } action: {
                        editor.islandFrame = $0
                    }
                    .onDisappear { editor.islandFrame = .zero }
                    .allowsHitTesting(false)
                HomeRoom(
                    layout: editor.displayLayout, catalog: model.viewModel.settings.widgetDescriptor(for:),
                    headerHeight: headerHeight)
            }
            IslandView(viewModel: model.viewModel, acceptsDrops: false)
                .environment(\.homeEditor, isEditingHome ? editor : nil)
                .environment(\.tabEditor, isEditingTabs ? tabEditor : nil)
                .overlay(alignment: .top) {
                    // Only what is being edited takes clicks: the tab strip is look-only while editing Home, and the
                    // content is look-only while editing tabs.
                    if isEditingHome {
                        Color.clear
                            .frame(height: headerHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {}
                    } else if isEditingTabs {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: headerHeight)
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {}
                        }
                    }
                }
                .allowsHitTesting(isEditingHome || isEditingTabs)
        }
        .frame(width: ScreenGeometry.panelSize.width, height: Theme.Metrics.previewBandHeight, alignment: .top)
    }
}

/// A two-finger horizontal swipe over the preview, as on the island itself. A local scroll monitor, so it hears the
/// gesture whatever is on top (the preview is look-only). One swipe acts once.
struct PreviewSwipe: NSViewRepresentable {
    let onSwipe: (Swipe) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.onSwipe = onSwipe }

    final class MonitorView: NSView {
        var onSwipe: ((Swipe) -> Void)?

        /// Only listens for scrolls, through a monitor: it must never take a click from the controls above it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private var monitor: Any?
        private var recognizer = SwipeRecognizer()

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.window === window, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty,
                bounds.contains(convert(event.locationInWindow, from: nil))
            else { return }
            let swipe = recognizer.add(
                dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, inverted: event.isDirectionInvertedFromDevice,
                began: event.phase.contains(.began))
            if let swipe { onSwipe?(swipe) }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// The island and the menu bar in one band, and where each is between the two views. `Animatable`, so the body sees every value
/// on the way (not just the two ends) and the parts can move at their own pace: the island shrinks toward the notch as it slides
/// out, the menu bar arrives as it slides in, and its window opens a beat later, from the strip.
private struct BandSlide<Island: View, MenuBar: View>: View, Animatable {
    var progress: Double
    let island: () -> Island
    let menu: (Double) -> MenuBar

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(max(progress, 0), 1)
        // The menu bar's window opens over the second part of the slide.
        let reveal = min(max((p - 0.35) / 0.65, 0), 1)
        GeometryReader { geometry in
            ZStack {
                island()
                    .scaleEffect(1 - 0.28 * p, anchor: .top)
                    .offset(x: -p * geometry.size.width)
                    .opacity(1 - min(p * 1.6, 1))
                    .allowsHitTesting(p < 0.5)
                // Not built while it is entirely away, so nothing in it runs.
                if p > 0.001 {
                    menu(reveal)
                        .offset(x: (1 - p) * geometry.size.width)
                        .opacity(min(p * 2, 1))
                        .allowsHitTesting(p > 0.5)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}
