import SwiftUI

/// The Settings window: a sidebar of panes, and beside each pane's controls a live preview of the island.
/// Personal choices only. What the island shows and where is a setting; how it looks is not.
struct SettingsView: View {
    let settings: AppSettings
    let features: IslandFeatures
    /// Where the tour stands; nil in a preview or a test, where there is no tour.
    let onboarding: OnboardingState?

    @AppStorage("settings.pane") private var storedPane = SettingsPane.general.rawValue
    /// Hidden, the window is all pane; the pane's own icon, where the hide button was, brings the sidebar back.
    @State private var sidebarHidden = UserDefaults.standard.bool(forKey: SettingsView.sidebarHiddenKey)
    @State private var searchText = ""
    /// A section a search result pointed at, until the pane has scrolled to it.
    @State private var scrollTarget: String?
    @State private var preview: IslandPreviewModel?
    @State private var editor: HomeEditor
    @State private var tabEditor: TabEditor
    @State private var anchors = TourAnchors()
    @State private var tour: SettingsTour
    @State private var tourKeys = TourKeyMonitor()
    /// The running tour changed the preview (a stop with its own view), so the pane's own view comes back when it moves on.
    @State private var tourChangedPreview = false
    @Environment(\.undoManager) private var undoManager

    init(settings: AppSettings, features: IslandFeatures, onboarding: OnboardingState? = nil) {
        self.settings = settings
        self.features = features
        self.onboarding = onboarding
        _editor = State(initialValue: HomeEditor(settings: settings))
        _tabEditor = State(initialValue: TabEditor(settings: settings))
        _tour = State(initialValue: SettingsTour(onFinish: { onboarding?.finishTour() }))
    }

    private var pane: SettingsPane { SettingsPane(rawValue: storedPane) ?? .general }

    /// The panes are laid out for this much width: a wider window centers them instead of stretching every row.
    static let maxContentWidth: CGFloat = 900
    /// Space above the first row, where the traffic lights float: the sidebar's search and the preview's switcher share the line
    /// below it, and a pane with no preview leaves room for that line too.
    static let chromeHeight: CGFloat = 40
    static let rowHeight: CGFloat = 28
    /// The sidebar is a quarter of the window, within these limits, so it grows and shrinks with it.
    static func sidebarWidth(for windowWidth: CGFloat) -> CGFloat { min(max(windowWidth * 0.24, 190), 260) }
    static let sidebarAnimation = Animation.smooth(duration: 0.42)
    static let sidebarHiddenKey = "settings.sidebarHidden"
    /// The narrowest the window goes: the preview is 560 wide and needs its margins, with or without the sidebar beside it.
    static let minWidthWithSidebar: CGFloat = 830
    static let minWidthWithoutSidebar: CGFloat = 640

    var body: some View {
        GeometryReader { geometry in
            let sidebarWidth = Self.sidebarWidth(for: geometry.size.width)
            HStack(spacing: 0) {
                // The sidebar is always there, and its width is what slides to nothing and back: a view that came and went would
                // snap, and the panes beside it would jump to fill the space.
                SettingsSidebar(
                    selection: Binding(get: { pane }, set: { storedPane = $0.rawValue }), searchText: $searchText,
                    hideSidebar: { setSidebar(hidden: true) }, onOpen: open
                )
                .padding(.top, Self.chromeHeight)
                .frame(width: sidebarWidth)
                .background(SidebarBackground().ignoresSafeArea())
                .overlay(alignment: .trailing) { Divider().ignoresSafeArea() }
                .frame(width: sidebarHidden ? 0 : sidebarWidth, alignment: .leading)
                .clipped()
                .opacity(sidebarHidden ? 0 : 1)
                .allowsHitTesting(!sidebarHidden)
                .accessibilityHidden(sidebarHidden)
                .zIndex(1)
                detail
            }
            .animation(Self.sidebarAnimation, value: sidebarHidden)
            // The tour's anchors and its overlay share one space, so the ring is placed in the coordinates the anchors report.
            .environment(\.tourAnchors, anchors)
            .coordinateSpace(.named(TourAnchors.space))
            .overlay {
                SettingsTourOverlay(
                    tour: tour, anchors: anchors, unavailable: sidebarHidden ? [.search] : [],
                    onShowMe: { scrollTarget = tour.current?.scrollAnchor })
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(
            minWidth: sidebarHidden ? Self.minWidthWithoutSidebar : Self.minWidthWithSidebar, idealWidth: 900,
            minHeight: 600, idealHeight: 760
        )
        .onAppear {
            settings.refresh()
            editor.undoManager = undoManager
            editor.watchesMouseUp = true
            // Opened for a widget ("Edit Home..."): the tour doesn't pull the person away from it.
            let opensForAWidget = settings.requestedHomeSelection != nil
            takeRequestedSelection()
            let model = IslandPreviewModel(live: features)
            preview = model
            tabEditor.preview = model
            editor.previewModel = model
            showPreview(for: pane)
            if let onboarding, onboarding.needsTour || onboarding.tourRequested, !opensForAWidget,
                !OnboardingWindowController.shared.isOpen
            {
                beginTour()
            }
        }
        .onDisappear {
            if tour.isRunning { tour.end() }
            tourKeys.stop()
            preview?.stop()
            preview = nil
        }
        .onChange(of: storedPane) {
            showPreview(for: pane)
            // A pane chosen in the sidebar: the tour follows.
            tour.jump(to: pane)
        }
        .onChange(of: tour.index) { old, new in
            if new != nil {
                applyStop()
                if let stop = tour.current {
                    AccessibilityNotification.Announcement("\(stop.title). \(stop.copy)").post()
                }
            } else if old != nil {
                endTour()
            }
        }
        .onChange(of: onboarding?.tourRequested) { _, requested in
            if requested == true, !OnboardingWindowController.shared.isOpen { beginTour() }
        }
        .onChange(of: sidebarHidden) { _, hidden in UserDefaults.standard.set(hidden, forKey: Self.sidebarHiddenKey) }
        .onChange(of: settings.requestedHomeSelection) { takeRequestedSelection() }
    }

    /// The pane: the preview with its switcher on the top line, then the controls; or, for a pane with no preview, just the controls
    /// under that line. The Home editor's drags start in the preview or in Add Widgets and end in either, so both share one space,
    /// and the widget being dragged is drawn over the whole pane.
    private var detail: some View {
        VStack(spacing: 0) {
            if pane.previewContext != nil, let preview {
                IslandPreview(
                    model: preview, editor: pane == .home ? editor : nil, tabEditor: pane == .tabs ? tabEditor : nil)
                Divider()
            } else {
                Color.clear.frame(height: Self.chromeHeight + Self.rowHeight + 8)
            }
            ScrollViewReader { proxy in
                content
                    .tourAnchor(.paneViewport)
                    .task(id: scrollTarget) { await scroll(to: scrollTarget, with: proxy) }
            }
        }
        .padding(.top, pane.previewContext != nil && preview != nil ? Self.chromeHeight - 12 : 0)
        .frame(maxWidth: Self.maxContentWidth)
        .frame(maxWidth: .infinity)
        .coordinateSpace(.named(HomeEditor.space))
        .overlay { if pane == .home { HomeDragLayer(editor: editor) } }
        .overlay(alignment: .topLeading) { if sidebarHidden { showSidebarButton } }
    }

    /// With the sidebar hidden: the standard sidebar icon, on the line the hide button was on, brings it back.
    private var showSidebarButton: some View {
        SidebarToggleButton(systemImage: "sidebar.left", help: "Show Sidebar", action: { setSidebar(hidden: false) })
            .frame(width: Self.rowHeight, height: Self.rowHeight)
            .padding(.leading, 16)
            .padding(.top, Self.chromeHeight)
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topLeading)))
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .general: GeneralPane(settings: settings)
        case .tabs: TabsPane(settings: settings, preview: preview)
        case .home: HomePane(settings: settings, features: features, preview: preview, editor: editor)
        case .shelf: ShelfPane(settings: settings, preview: preview)
        case .media: MediaPane(settings: settings)
        case .tools: ToolsPane(settings: settings, preview: preview)
        case .notifications: NotificationsPane(settings: settings, preview: preview)
        case .privacy: PrivacyPane(settings: settings)
        }
    }

    private func setSidebar(hidden: Bool) {
        withAnimation(Self.sidebarAnimation) { sidebarHidden = hidden }
    }

    /// A search result: go to its pane, and to its section.
    private func open(_ entry: SettingsSearchEntry) {
        storedPane = entry.pane.rawValue
        searchText = ""
        scrollTarget = entry.anchor
    }

    /// Scrolls a pane to a section once the pane is on screen.
    private func scroll(to anchor: String?, with proxy: ScrollViewProxy) async {
        guard let anchor else { return }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(anchor, anchor: .top) }
        scrollTarget = nil
    }

    /// Right-click, Edit Home\u{2026} in the island: select that widget.
    private func takeRequestedSelection() {
        guard let id = settings.requestedHomeSelection else { return }
        editor.selection = id
        settings.requestedHomeSelection = nil
    }

    private func showPreview(for pane: SettingsPane) {
        // Menu Bar is a view of the preview only where its icons are chosen.
        preview?.allowsMenuBar = pane == .tabs
        if let context = pane.previewContext { preview?.show(context) }
        // A stop that shows its own view keeps it while the tour is on that stop's pane.
        if let stop = tour.current, stop.pane == pane, let context = stop.preview { preview?.show(context) }
    }

    // MARK: Tour

    /// Shows the sidebar (stop 1 points at its search field), starts at the first stop, and listens for Return.
    private func beginTour() {
        onboarding?.tourRequested = false
        if sidebarHidden { setSidebar(hidden: false) }
        tour.start()
        applyStop()
        tourKeys.start(in: { SettingsWindowController.shared.window }) { tour.next() }
    }

    /// Takes the window to the current stop: its pane, its view in the preview, and its place in the pane.
    private func applyStop() {
        guard let stop = tour.current else { return }
        if pane != stop.pane { storedPane = stop.pane.rawValue }
        if let context = stop.preview {
            preview?.allowsMenuBar = stop.pane == .tabs
            preview?.show(context)
            tourChangedPreview = true
        } else if tourChangedPreview {
            showPreview(for: stop.pane)
            tourChangedPreview = false
        }
        scrollTarget = stop.scrollAnchor
    }

    /// The tour ended: the pane's own preview comes back, and Return is Return again.
    private func endTour() {
        tourKeys.stop()
        if tourChangedPreview {
            tourChangedPreview = false
            showPreview(for: pane)
        }
    }
}
