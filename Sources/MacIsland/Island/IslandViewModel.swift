import SwiftUI

/// The island's features. The tab strip shows `Theme.Metrics.maxTabs` of them, chosen in Settings.
enum IslandModule: String, CaseIterable, Identifiable {
    case home, media, shelf, clock, reminders, tools, agents, notes

    var id: Self { self }

    /// Modules that have a view. Settings offers only these.
    var isAvailable: Bool {
        switch self {
        case .home, .media, .shelf, .clock, .reminders, .tools, .notes: true
        case .agents: false
        }
    }

    /// Another way into a module that isn't in the tab strip, for Settings to mention.
    var otherWayIn: String? {
        switch self {
        case .notes: "Also opens from the pencil beside the tabs"
        case .shelf: "Also opens when you drop a file, and from Home"
        case .clock: "Also opens from Home’s timers"
        case .media: "Also opens from Home’s music"
        default: nil
        }
    }

    static let defaultTabs: [IslandModule] = [.home, .media, .clock, .reminders, .tools]

    /// The strip before Reminders got its own tab, so an unchanged one can move to the new default.
    static let previousDefaultTabs: [IslandModule] = [.home, .media, .shelf, .clock, .tools]

    var title: String {
        switch self {
        case .home: "Home"
        case .media: "Media"
        case .shelf: "Shelf"
        case .clock: "Clock"
        case .reminders: "Reminders"
        case .tools: "Tools"
        case .agents: "Agents"
        case .notes: "Notes"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .media: "music.note"
        case .shelf: "tray.full"
        case .clock: "timer"
        case .reminders: "checklist"
        case .tools: "square.grid.2x2"
        case .agents: "sparkles"
        case .notes: "note.text"
        }
    }
}

enum ClockMode: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case stopwatch = "Stopwatch"
    case pomodoro = "Pomodoro"

    var id: Self { self }
}

/// A short message beside the notch (charging, color copied, timer done).
struct IslandAlert: Equatable {
    let id = UUID()
    var systemImage: String
    var tint: Color
    var text: String
    /// Stays until the person opens the island, instead of timing out.
    var staysUntilSeen = false
    /// Off when the tint is arbitrary content (a picked color) that may not be legible as text.
    var tintsText = true
    /// The tab to show when the person opens the island because of this alert.
    var opensTab: IslandModule?
    /// The glyph is drawn as a `ChargingBadge`, with a ring circling the bolt.
    var isCharging = false
}

/// A wider, momentary announcement below the notch, with at most one action.
struct IslandBanner: Equatable {
    struct Action {
        let title: String
        let perform: @MainActor () -> Void
    }

    let id = UUID()
    var systemImage: String
    var tint: Color
    var title: String
    var detail: String?
    var action: Action?

    static func == (lhs: IslandBanner, rhs: IslandBanner) -> Bool { lhs.id == rhs.id }
}

/// What the collapsed island shows, highest priority first.
enum CompactActivity: Equatable {
    case banner(IslandBanner)
    case alert(IslandAlert)
    case microphone
    case timer
    case pomodoro
    case stopwatch
    case working(String)
    case transfer
    case media
    case none
}

/// Everything the island's views read. Created live by the app and with test doubles in tests.
struct IslandFeatures {
    let nowPlaying: NowPlayingModel
    let outputs: AudioOutputs
    let shelf: ShelfModel
    let timer: TimerModel
    let stopwatch: StopwatchModel
    let keepAwake: KeepAwake
    let lowPower: LowPowerMode
    let ringLight: RingLight
    let micMute: MicrophoneMute
    let privacy: PrivacyMonitor
    let transfers: TransferMonitor
    let network: NetworkMonitor
    let settings: AppSettings
    let agenda: AgendaMonitor
    let focus: FocusMode
    let clipboard: ClipboardHistory
    let batteries: DeviceBatteries
    let pomodoro: PomodoroModel
    let work: WorkTracker
    let weather: WeatherModel
    let fileTools: FileTools
    let notes: NotesModel
    let keyboardCleaner: KeyboardCleaner
    let launch: LaunchModel
    let stats: SystemStats
    let rates: ExchangeRates
}

@MainActor
@Observable
@dynamicMemberLookup
final class IslandViewModel {
    enum State: Equatable {
        case compact
        /// The pointer rests on the island: the top activity at full size, no tabs.
        case peek
        case expanded
    }

    let features: IslandFeatures
    var geometry = ScreenGeometry.current()
    var selectedTab: IslandModule = .home
    var clockMode: ClockMode = .timer
    var notesMode = NotesMode.notes
    var state: State = .compact {
        didSet {
            if state == .compact {
                toolsExpanded = false
                calendarExpanded = false
            }
        }
    }
    /// The Tools tab shows every tool instead of just the pinned row.
    private(set) var toolsExpanded = false
    /// Home shows the month calendar instead of the agenda.
    private(set) var calendarExpanded = false
    var shelfMode: ShelfMode = .files
    /// The Shelf file being previewed with Quick Look.
    var quickLookURL: URL?
    /// The Shelf file under the pointer, which Space previews.
    @ObservationIgnored private(set) var hoveredShelfItem: URL?
    /// Asks the app to give the island the keyboard (set by the app, which owns the panel).
    @ObservationIgnored var onWantsKeyboard: (() -> Void)?
    private(set) var alert: IslandAlert?
    private(set) var banner: IslandBanner?
    /// A file from another app is being dragged: the compact island grows into a bigger target.
    private(set) var isFileDragActive = false
    /// The pointer is resting on the compact island and the peek hasn't opened yet.
    private(set) var isSwelling = false

    /// Opens a module in its own window. Set by the app, which owns the windows.
    @ObservationIgnored var onOpenWindow: ((IslandModule) -> Void)?
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var bannerFollowUp: IslandAlert?
    @ObservationIgnored private var isHovering = false
    /// Opened from the keyboard: stays open with the pointer elsewhere until Esc, the hotkey, or a click outside.
    @ObservationIgnored private(set) var isPinnedOpen = false

    init(features: IslandFeatures) {
        self.features = features
    }

    subscript<T>(dynamicMember keyPath: KeyPath<IslandFeatures, T>) -> T {
        features[keyPath: keyPath]
    }

    /// Everything live, highest priority first. The island shows the top two.
    var compactActivities: [CompactActivity] {
        if let banner { return [.banner(banner)] }
        var list: [CompactActivity] = []
        if let alert { list.append(.alert(alert)) }
        if features.privacy.isMicrophoneInUse { list.append(.microphone) }
        if features.timer.isActive { list.append(.timer) }
        if features.pomodoro.isActive { list.append(.pomodoro) }
        if features.stopwatch.isActive { list.append(.stopwatch) }
        if let job = features.work.current { list.append(.working(job.title)) }
        if !features.transfers.transfers.isEmpty { list.append(.transfer) }
        if features.nowPlaying.state.hasMedia { list.append(.media) }
        return list
    }

    /// The top activity.
    var compactActivity: CompactActivity { compactActivities.first ?? .none }

    /// Whether the strip beside the notch has live status to show: a running clock, or a glyph for hotspot,
    /// Ring Light, Keep Awake, or a locked keyboard.
    var hasStatusIndicators: Bool {
        let clockRunning = features.timer.isActive || features.pomodoro.isActive || features.stopwatch.isRunning
        return (clockRunning && selectedTab != .clock)
            || features.keyboardCleaner.isLocked || features.network.isOnHotspot
            || features.ringLight.isOn || features.keepAwake.isOn
    }

    /// What fits between the notch and the island's right edge.
    var trailingStripWidth: CGFloat {
        (Theme.Metrics.expandedWidth - geometry.notchSize.width) / 2 - ScreenGeometry.topFlare - 10
    }

    private var trailingStripPlan: TrailingStrip.Plan {
        TrailingStrip.plan(
            available: trailingStripWidth,
            rightTabs: features.settings.rightTabs.count,
            hasStatus: hasStatusIndicators,
            hasWeather: features.weather.conditions != nil,
            hasNotesTab: features.settings.isInTabs(.notes)
        )
    }

    /// The New Note pencil, when there is room and Notes isn't already a tab.
    var showsStripPencil: Bool { trailingStripPlan.pencil }

    /// The weather, whenever it fits beside the tab, the status, and Settings: it must never crowd the notch.
    var showsStripWeather: Bool { trailingStripPlan.weather }

    /// Two activities as a minimal pair: leading is the top rank, trailing the second. An alert
    /// always stands alone, since its text is the message.
    var compactPair: (leading: CompactActivity, trailing: CompactActivity)? {
        let list = compactActivities
        guard list.count >= 2 else { return nil }
        if case .alert = list[0] { return nil }
        return (list[0], list[1])
    }

    /// Width added on each side of the notch. Leading and trailing stay equal so the
    /// two halves read as one piece.
    private var compactSideWidth: CGFloat {
        if compactPair != nil { return geometry.notchSize.height + 8 }
        switch compactActivity {
        case .banner, .none: return 0
        case .alert: return 64
        case .microphone: return 60
        case .timer, .pomodoro, .stopwatch, .transfer: return 52
        case .working: return 64
        case .media: return geometry.notchSize.height + 8
        }
    }

    var presentation: IslandPresentation {
        switch state {
        case .compact: banner == nil ? .compact : .banner
        case .peek: .peek
        case .expanded: .expanded
        }
    }

    /// A pill on a display without a notch has no hardware to hide behind, so it is not drawn
    /// while nothing is live. Its hover zone stays.
    var isPillHidden: Bool {
        !geometry.hasNotch && presentation == .compact && compactActivity == .none && !showsDragTarget
    }

    /// Clock for a running timer or stopwatch, Now Playing for music, and the day at a glance when idle.
    var peekContentHeight: CGFloat {
        switch compactActivity {
        case .timer, .pomodoro, .stopwatch: Theme.Metrics.glanceHeight
        case .media: mediaContentHeight(peek: true)
        default: Theme.Metrics.idlePeekHeight
        }
    }

    /// The music player: the art, the scrubber, and the transport, a few points apart, and the lyric line when there is one. The
    /// Media tab has bigger art and sits a little lower than the peek. With nothing playing it is a single line.
    func mediaContentHeight(peek: Bool) -> CGFloat {
        guard features.nowPlaying.state.hasMedia else { return Theme.Metrics.glanceHeight }
        let art = peek ? Theme.Metrics.playerPeekArtwork : Theme.Metrics.playerArtwork
        let inset = peek ? 0 : Theme.Metrics.playerTopInset
        let lyrics = features.nowPlaying.lyrics.lines.isEmpty ? 0 : Theme.Metrics.lyricsRowHeight
        let gap = Theme.Metrics.playerSpacing
        return inset + art + gap + Theme.Metrics.playerScrubber + gap + Theme.Metrics.playerTransport + lyrics
    }

    var showsDragTarget: Bool { isFileDragActive && presentation == .compact }

    func setFileDragActive(_ active: Bool) {
        guard active != isFileDragActive else { return }
        withAnimation(Theme.Motion.track) { isFileDragActive = active }
    }

    /// Height of the selected module below the notch.
    var currentContentHeight: CGFloat { contentHeight(for: selectedTab) }

    func contentHeight(for tab: IslandModule) -> CGFloat {
        switch tab {
        case .home: calendarExpanded ? Theme.Metrics.homeMonthHeight : Theme.Metrics.homeContentHeight
        case .media: mediaContentHeight(peek: false)
        case .shelf: Theme.Metrics.shelfHeight
        case .clock:
            Theme.Metrics.clockRing + (clockMode == .pomodoro ? Theme.Metrics.pomodoroStatsHeight : 0)
        case .tools: (toolsExpanded ? Theme.Metrics.toolsGridHeight : Theme.Metrics.toolsRowHeight)
            + (features.ringLight.isOn ? Theme.Metrics.ringLightControlsHeight : 0)
            + (features.keepAwake.isOn ? Theme.Metrics.keepAwakeChipsHeight : 0)
        case .notes: Theme.Metrics.notesHeight
        case .reminders: Theme.Metrics.remindersHeight
        case .agents: Theme.Metrics.glanceHeight
        }
    }

    var size: CGSize {
        switch presentation {
        case .compact:
            if isPillHidden { return .zero }
            var size = geometry.compactSize
            size.width += 2 * compactSideWidth
            if showsDragTarget {
                size.width = max(size.width, geometry.compactSize.width + 2 * Theme.Metrics.dragTargetInset)
                size.height += Theme.Metrics.dragTargetHeight
            }
            return size
        case .banner:
            return CGSize(
                width: Theme.Metrics.bannerWidth,
                height: geometry.notchSize.height + Theme.Metrics.bannerContentHeight
            )
        case .peek:
            return CGSize(width: Theme.Metrics.peekWidth, height: hangingHeight(peekContentHeight))
        case .expanded:
            return CGSize(width: Theme.Metrics.expandedWidth, height: hangingHeight(currentContentHeight))
        }
    }

    /// The notch, the gap above the content, the content, and the bottom margin.
    private func hangingHeight(_ contentHeight: CGFloat) -> CGFloat {
        geometry.notchSize.height + Theme.Metrics.contentTopGap + contentHeight + Theme.Metrics.margin
    }

    /// Area that counts as "over the island", in screen coordinates.
    var hitRect: CGRect { geometry.islandRect(for: isPillHidden ? geometry.compactSize : size) }

    /// The compact play/pause control. Hovering it doesn't open the island, so it can be clicked.
    var compactControlRect: CGRect? {
        guard presentation == .compact, compactActivity == .media, compactPair == nil else { return nil }
        let rect = hitRect
        let start = geometry.screenFrame.midX + geometry.notchSize.width / 2
        return CGRect(x: start, y: rect.minY, width: rect.maxX - start, height: rect.height)
    }

    func select(_ tab: IslandModule) {
        withAnimation(Theme.Motion.resize) {
            selectedTab = tab
        }
    }

    /// Typing needs the island to stay put: it stays open until Esc, the shortcut, or a click outside.
    /// The pencil beside the tabs: a fresh note, on the Notes tab even if it isn't in the strip.
    func openQuickNote() {
        features.notes.addNote()
        withAnimation(Theme.Motion.resize) {
            notesMode = .notes
            selectedTab = .notes
        }
    }

    /// Home's timer chips and cards go to the Clock tab in the mode that is running.
    func openClock(_ mode: ClockMode) {
        withAnimation(Theme.Motion.resize) {
            clockMode = mode
            selectedTab = .clock
        }
    }

    func openWindow(_ module: IslandModule) { onOpenWindow?(module) }

    /// Opens the island on a module, whether or not it is one of the tabs.
    func show(_ module: IslandModule) {
        selectedTab = module
        open()
    }

    /// Runs one of the person's Shortcuts. It shows as work in progress while it runs.
    func runShortcut(_ name: String) {
        let job = features.work.begin("Running")
        Task {
            let finished = await ShortcutsCLI.run(shortcut: name)
            features.work.end(job)
            if finished {
                flash(IslandAlert(systemImage: "checkmark.circle.fill", tint: Theme.Tint.positive, text: "Done"), respectingFocus: false)
            } else {
                showBanner(
                    IslandBanner(
                        systemImage: "square.2.layers.3d",
                        tint: Theme.Tint.attention,
                        title: "\u{201C}\(name)\u{201D} Didn\u{2019}t Finish",
                        detail: "Open it in Shortcuts to see why"
                    ),
                    for: .seconds(6),
                    respectingFocus: false
                )
            }
        }
    }

    func setNotesMode(_ mode: NotesMode) {
        withAnimation(Theme.Motion.resize) { notesMode = mode }
    }

    func holdOpen() {
        hoverTask?.cancel()
        isPinnedOpen = true
    }

    func copySnippet(_ snippet: Snippet) {
        features.clipboard.copyText(snippet.text)
        flash(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
    }

    func setCalendarExpanded(_ expanded: Bool) {
        withAnimation(Theme.Motion.resize) { calendarExpanded = expanded }
    }

    /// Saves a reminder from Home, and says how it went.
    func addReminder(_ title: String) {
        Task {
            if await features.agenda.addReminder(title: title) {
                flash(
                    IslandAlert(systemImage: "checklist", tint: Theme.Tint.positive, text: "Added"),
                    respectingFocus: false
                )
            } else {
                showBanner(
                    IslandBanner(
                        systemImage: "checklist",
                        tint: Theme.Tint.attention,
                        title: "Reminders Access Is Off",
                        detail: "Allow it to add reminders",
                        action: .init(title: "Allow Access") { AgendaMonitor.openRemindersSettings() }
                    ),
                    for: .seconds(6),
                    respectingFocus: false
                )
            }
        }
    }

    func setToolsExpanded(_ expanded: Bool) {
        withAnimation(Theme.Motion.resize) { toolsExpanded = expanded }
    }

    func setShelfMode(_ mode: ShelfMode) {
        withAnimation(Theme.Motion.resize) { shelfMode = mode }
    }

    func setHoveredShelfItem(_ url: URL?) {
        hoveredShelfItem = url
        if url != nil { onWantsKeyboard?() }
    }

    /// Quick Look for a Shelf file. The island stays open while the preview is up.
    func showQuickLook(_ url: URL) {
        holdOpen()
        NSApp.activate()
        quickLookURL = url
    }

    /// Space over a Shelf file. Returns `false` when there is nothing to preview, so the key passes on.
    func quickLookHoveredItem() -> Bool {
        guard state == .expanded, selectedTab == .shelf, shelfMode == .files, let url = hoveredShelfItem,
            features.shelf.items.contains(url)
        else { return false }
        showQuickLook(url)
        return true
    }

    /// Runs a clipboard card's action.
    func perform(_ action: SmartAction) {
        switch action {
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .email(let address):
            if let url = URL(string: "mailto:\(address)") { NSWorkspace.shared.open(url) }
        case .color(_, let rgb):
            features.clipboard.copyText(rgb)
            flash(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
        }
    }

    /// Copies a palette answer (a conversion, a sum) and says so.
    func copyAnswer(_ text: String) {
        features.clipboard.copyText(text)
        flash(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
    }

    /// Puts a text card back on the pasteboard as plain text only (no other types).
    func copyPlainText(_ entry: ClipboardEntry) {
        guard case .text(let text) = entry.content else { return }
        features.clipboard.copyText(text)
        flash(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
    }

    /// Keeps a text card as a snippet in Notes.
    func saveAsSnippet(_ entry: ClipboardEntry) {
        guard case .text(let text) = entry.content else { return }
        features.notes.saveSnippet(text: text)
        flash(IslandAlert(systemImage: "text.badge.plus", tint: Theme.Tint.positive, text: "Saved"), respectingFocus: false)
    }

    func copyFromClipboardHistory(_ entry: ClipboardEntry) {
        features.clipboard.copy(entry)
        flash(IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"), respectingFocus: false)
    }

    func setClockMode(_ mode: ClockMode) {
        withAnimation(Theme.Motion.resize) { clockMode = mode }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverTask?.cancel()

        // A banner holds still while the pointer is on it, then leaves shortly after.
        if banner != nil {
            if hovering {
                bannerTask?.cancel()
            } else {
                scheduleBannerDismissal(after: .seconds(1.5))
            }
            return
        }

        // The pointer takes over from the keyboard; leaving doesn't close a pinned island.
        if hovering { isPinnedOpen = false }
        if isPinnedOpen { return }

        if hovering {
            guard state == .compact else { return }
            if !isPillHidden { withAnimation(Theme.Motion.track) { isSwelling = true } }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Theme.Timing.peekDwell)
                guard !Task.isCancelled, let self else { return }
                if case .stopwatch = self.compactActivity { self.clockMode = .stopwatch }
                if case .timer = self.compactActivity { self.clockMode = .timer }
                if case .pomodoro = self.compactActivity { self.clockMode = .pomodoro }
                withAnimation(Theme.Motion.open) {
                    self.isSwelling = false
                    self.revealPendingAlert()
                    self.state = .peek
                }
            }
        } else {
            if isSwelling { withAnimation(Theme.Motion.track) { isSwelling = false } }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Theme.Timing.closeDelay)
                guard !Task.isCancelled, let self, self.state != .compact else { return }
                withAnimation(Theme.Motion.close) { self.state = .compact }
            }
        }
    }

    /// Opening the island counts as seeing an alert that stays until seen.
    private func revealPendingAlert() {
        guard let alert, alert.staysUntilSeen else { return }
        if let tab = alert.opensTab { selectedTab = tab }
        self.alert = nil
    }

    /// Click, swipe down, or the shortcut: the full island with tabs.
    func open() {
        hoverTask?.cancel()
        bannerTask?.cancel()
        withAnimation(Theme.Motion.open) {
            isSwelling = false
            banner = nil
            revealPendingAlert()
            state = .expanded
        }
    }

    /// The hotkey: open and pin the island, or close it.
    func toggleFromKeyboard() {
        if state == .expanded {
            closePinned()
            return
        }
        isPinnedOpen = true
        open()
    }

    func closePinned() {
        isPinnedOpen = false
        hoverTask?.cancel()
        withAnimation(Theme.Motion.close) { state = .compact }
    }

    /// Left/right arrow: move to the neighboring tab, without wrapping.
    func selectAdjacentTab(_ step: Int) {
        let tabs = visibleTabs()
        guard let index = tabs.firstIndex(of: selectedTab) else { return }
        let next = index + step
        guard tabs.indices.contains(next) else { return }
        select(tabs[next])
    }

    func visibleTabs() -> [IslandModule] { features.settings.tabs }
    func leftTabs() -> [IslandModule] { features.settings.leftTabs }
    func rightTabs() -> [IslandModule] { features.settings.rightTabs }

    func setDropTargeted(_ targeted: Bool) {
        guard targeted else { return }
        hoverTask?.cancel()
        isHovering = true
        withAnimation(Theme.Motion.open) {
            selectedTab = .shelf
            shelfMode = .files
            state = .expanded
        }
    }

    /// While a Focus is on and the person asked for quiet, only alerts that stay until seen get through.
    private var isQuiet: Bool { features.settings.quietDuringFocus && features.focus.isFocused }

    /// `respectingFocus: false` is for feedback to something the person just did.
    func flash(_ alert: IslandAlert, for duration: Duration = .seconds(3), respectingFocus: Bool = true) {
        if respectingFocus, isQuiet, !alert.staysUntilSeen { return }
        alertTask?.cancel()
        withAnimation(Theme.Motion.open) { self.alert = alert }
        guard !alert.staysUntilSeen else { return }
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Theme.Motion.close) { self.alert = nil }
        }
    }

    /// Shows a banner, then optionally leaves `followUp` as a compact alert.
    func showBanner(
        _ banner: IslandBanner,
        for duration: Duration = .seconds(4),
        followUp: IslandAlert? = nil,
        respectingFocus: Bool = true
    ) {
        if respectingFocus, isQuiet {
            if let followUp { flash(followUp) }
            return
        }
        bannerTask?.cancel()
        bannerFollowUp = followUp
        isPinnedOpen = false
        withAnimation(Theme.Motion.open) {
            state = .compact
            self.banner = banner
        }
        if !isHovering { scheduleBannerDismissal(after: duration) }
    }

    func performBannerAction() {
        banner?.action?.perform()
        bannerFollowUp = nil
        dismissBanner()
    }

    private func scheduleBannerDismissal(after duration: Duration) {
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    private func dismissBanner() {
        bannerTask?.cancel()
        withAnimation(Theme.Motion.close) { banner = nil }
        if let followUp = bannerFollowUp {
            bannerFollowUp = nil
            flash(followUp)
        }
    }
}

/// What the strip right of the notch can hold. Settings, the right-hand tab, and live status come first, then
/// the weather, then the New Note pencil, so nothing ever reaches the notch. The pencil is left out when Notes
/// is already a tab. Widths are the largest each can be.
enum TrailingStrip {
    static let settings: CGFloat = 28
    static let tab: CGFloat = 28
    /// A running clock with a status glyph beside it, at its widest ("1:25:00").
    static let status: CGFloat = 72
    static let weather: CGFloat = 64
    static let pencil: CGFloat = 28
    static let spacing: CGFloat = 4

    struct Plan: Equatable {
        var weather: Bool
        var pencil: Bool
    }

    static func plan(available: CGFloat, rightTabs: Int, hasStatus: Bool, hasWeather: Bool, hasNotesTab: Bool = false) -> Plan {
        var used = settings + CGFloat(rightTabs) * (tab + spacing) + (hasStatus ? status + spacing : 0)
        let weatherFits = hasWeather && used + weather + spacing <= available
        if weatherFits { used += weather + spacing }
        let pencilFits = !hasNotesTab && used + pencil + spacing <= available
        return Plan(weather: weatherFits, pencil: pencilFits)
    }
}
