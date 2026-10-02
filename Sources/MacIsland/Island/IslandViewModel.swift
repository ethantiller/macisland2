import SwiftUI

/// The island's features. The tab strip shows `Theme.Metrics.maxTabs` of them, chosen in Settings.
enum IslandModule: String, CaseIterable, Identifiable {
    case home, media, shelf, clock, reminders, tools, agents, notes

    var id: Self { self }

    /// Modules that have a view. Settings offers only these.
    var isAvailable: Bool {
        switch self {
        case .home, .media, .shelf, .clock, .reminders, .tools, .notes, .agents: true
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
/// A reason the island stays open while the pointer is somewhere else. Reasons are named so two of them can't cancel each other:
/// ending a menu never lets go of Quick Look, and stopping Mirror never unpins the keyboard. The keyboard pin
/// (`IslandViewModel.isPinnedOpen`) is its own thing.
enum IslandHold: CaseIterable, Hashable {
    /// An AppKit menu is tracking: a context menu, a submenu, the share menu.
    case menu
    /// Quick Look is showing a Shelf file.
    case quickLook
    /// A panel or alert the island opened (a save panel, for example). Take it with `holding(_:during:)`.
    case panel
    /// A text field in the island has the keyboard.
    case textFocus
    /// The camera is on in Mirror. Never taken by name: it lasts exactly as long as the camera is on and working.
    case mirror

    /// Ends when the person closes the island or brings the pointer back, as the keyboard pin does. The others end only
    /// when what took them does, and a click outside does not close the island under them.
    var endsWithPointer: Bool { self == .textFocus }
}

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

/// What the volume and brightness HUD shows: each side until its own time is up, so both can show at once.
struct LevelHUD: Equatable {
    var volume: VolumeLevel?
    var brightness: Double?

    var isEmpty: Bool { volume == nil && brightness == nil }
    /// Both are showing, so the island splits around the notch: brightness leading, volume trailing.
    var isBoth: Bool { volume != nil && brightness != nil }
}

/// A wider, momentary announcement below the notch, with at most two actions. With two, the first is the main one.
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
    /// At most two; the first is prominent when there are two.
    var actions: [Action] = []
    /// When set, the glyph sits inside a ring of this color that draws once around it, as the charging alert's does.
    var ringTint: Color?
    /// When set, this agent's mark is drawn in place of the symbol (the symbol stays for accessibility).
    var agent: AgentKind?
    /// The tab to show when the person opens the island because of this banner.
    var opensTab: IslandModule?

    /// A banner with nothing to press is an alert: narrower than one with buttons, and its contents are centered.
    var isAlert: Bool { actions.isEmpty }

    static func == (lhs: IslandBanner, rhs: IslandBanner) -> Bool { lhs.id == rhs.id }
}

/// What the collapsed island shows, highest priority first.
/// What is being recorded. MacIsland records the screen and voice notes.
enum RecordingKind: Equatable {
    case screen, voice
}

/// What the Settings preview puts first on its island.
enum PreviewLead: Equatable {
    /// Nothing live shows except banners, alerts, and the levels.
    case idle
    /// This activity (by `choiceID`) leads the others.
    case activity(String)
}

enum CompactActivity: Equatable {
    case banner(IslandBanner)
    /// The volume and brightness HUD. It stands alone, like an alert.
    case levels(LevelHUD)
    case alert(IslandAlert)
    case recording(RecordingKind)
    case microphone
    case timer
    case pomodoro
    case stopwatch
    /// An event about to start, in the hour before it does.
    case countdown(AgendaItem)
    case working(String)
    /// An AI agent is working on a task.
    case agent
    case transfer
    case media
    /// Keep Awake, with the time it has left: a state, not a clock being timed, so it ranks last and stays white.
    case keepAwake
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
    let ringLight: RingLight
    let micMute: MicrophoneMute
    let privacy: PrivacyMonitor
    let transfers: TransferMonitor
    let network: NetworkMonitor
    let settings: AppSettings
    let agenda: AgendaMonitor
    let focus: FocusMode
    let clipboard: ClipboardHistory
    let pomodoro: PomodoroModel
    let work: WorkTracker
    let weather: WeatherModel
    let fileTools: FileTools
    let notes: NotesModel
    let keyboardCleaner: KeyboardCleaner
    let bluetooth: BluetoothDevices
    let mirror: CameraMirror
    let screenRecorder: ScreenRecorder
    let voice: VoiceRecorder
    let widgets: CustomWidgetValues
    let system: SystemModel
    let agents: AgentActivity
    let mixer: AppMixer
    let downloads: DownloadsFolder
    let notifications: NotificationMirror
}

@MainActor
@Observable
@dynamicMemberLookup
final class IslandViewModel {
    private struct ScrollArea {
        let frame: CGRect
        let axis: AxisLock.Axis
    }

    enum State: Equatable {
        case compact
        /// The pointer rests on the island: the top activity at full size, no tabs.
        case peek
        case expanded
    }

    let features: IslandFeatures
    var geometry = ScreenGeometry.current()
    @ObservationIgnored private var scrollAreas: [UUID: ScrollArea] = [:]
    var selectedTab: IslandModule = .home {
        didSet { if selectedTab != .tools { features.mirror.stop() } }
    }
    var clockMode: ClockMode = .timer
    /// The Media tab's output satellites and volume control are open, or the Mixer when it is on.
    var showsMediaOutputs = false
    var showsPeekOutputList = false
    private(set) var hoveredOutputSatelliteID: String?
    /// The activity the person chose to lead the closed island and the peek, by `CompactActivity.choiceID`. Memory only: it ends with
    /// the activity.
    var chosenActivityID: String?
    var agentsMode: AgentsMode = .now
    var usageRange: UsageRange = .today
    /// What the Stats mode counts: which tool, and over how long. In memory, like `usageRange`.
    var statsFilter: StatsFilter = .all
    var statsRange: StatsRange = .all
    var statsAgent: AgentKind? { statsFilter.agent }
    /// Where the timer dial's ruler is drawn while it is being scrubbed, in minutes. Nil when at rest.
    private(set) var dialPosition: Double?
    /// How far the ruler is stretched past 1 minute or the maximum, in points.
    private(set) var dialOverscroll: CGFloat = 0
    /// Where the dial's gesture would put the ruler with no limits; the value is this, held to the range.
    @ObservationIgnored private var dialRaw: Double?
    @ObservationIgnored private var dialAnchor = 0.0
    @ObservationIgnored private var dialAtEnd = false
    /// A tap on the trackpad's haptic engine. Tests replace it.
    @ObservationIgnored var dialHaptic: (NSHapticFeedbackManager.FeedbackPattern) -> Void = {
        NSHapticFeedbackManager.defaultPerformer.perform($0, performanceTime: .now)
    }
    var notesMode = NotesMode.notes
    var state: State = .compact {
        didSet {
            if state != .peek { showsPeekOutputList = false }
            if state == .compact {
                pruneChosenActivity()
                toolsExpanded = false
                calendarExpanded = false
                calendarSelectedDay = nil
                features.mirror.stop()
            }
        }
    }
    /// The Tools tab shows every tool instead of just the pinned row.
    private(set) var toolsExpanded = false
    /// Home shows the month calendar instead of the agenda.
    private(set) var calendarExpanded = false
    /// The day of the month chosen in the month view: the header names its first event. Esc and a second click put the month back.
    var calendarSelectedDay: Int?
    var shelfMode: ShelfMode
    /// The Shelf file being previewed with Quick Look.
    var quickLookURL: URL? {
        didSet {
            if quickLookURL != nil { hold(.quickLook) } else { release(.quickLook) }
        }
    }
    /// The Shelf file under the pointer, which Space previews.
    @ObservationIgnored private(set) var hoveredShelfItem: URL?
    /// Asks the app to give the island the keyboard (set by the app, which owns the panel).
    @ObservationIgnored var onWantsKeyboard: (() -> Void)?
    private(set) var alert: IslandAlert?
    /// The volume and brightness HUD, each side with its own expiry.
    private(set) var levels = LevelHUD()
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var brightnessTask: Task<Void, Never>?
    private(set) var banner: IslandBanner?
    /// A file from another app is being dragged: the compact island grows into a bigger target.
    private(set) var isFileDragActive = false
    /// The pointer is resting on the compact island and the peek hasn't opened yet.
    private(set) var isSwelling = false

    /// Opens a module in its own window. Set by the app, which owns the windows.
    @ObservationIgnored var onOpenWindow: ((IslandModule) -> Void)?
    /// Home's layout as the Settings editor is showing it while a widget is held over a spot. Only ever set on the preview's
    /// view model, so the real island never sees it.
    var homeLayoutOverride: HomeLayout?
    /// Only ever set on the Settings preview's view model, like `homeLayoutOverride`: what leads the island there.
    var previewLead: PreviewLead?

    /// The layout Home draws: the editor's preview while one is showing, otherwise the person's.
    var homeLayout: HomeLayout { homeLayoutOverride ?? features.settings.homeLayout }

    /// Opens Settings on a pane, with a Home widget selected. Set by the app, which owns the window.
    @ObservationIgnored var onOpenSettings: ((SettingsPane, UUID?) -> Void)?
    /// Lets the person choose what to record. Tests replace it.
    @ObservationIgnored var pickRegion: (@escaping (RegionSelection) -> Void) -> Void = {
        RegionPicker.shared.present(completion: $0)
    }
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var bannerFollowUp: IslandAlert?
    @ObservationIgnored private var isHovering = false
    /// Opened from the keyboard: stays open with the pointer elsewhere until Esc, the hotkey, or a click outside.
    @ObservationIgnored private(set) var isPinnedOpen = false
    /// What is holding the island open (see `IslandHold`), apart from the keyboard pin and Mirror, which is derived.
    @ObservationIgnored private(set) var holds: Set<IslandHold> = []
    /// Where the pointer is, in screen coordinates. Tests replace it.
    @ObservationIgnored var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    init(features: IslandFeatures) {
        self.features = features
        shelfMode = features.settings.shelfMode
    }

    subscript<T>(dynamicMember keyPath: KeyPath<IslandFeatures, T>) -> T {
        features[keyPath: keyPath]
    }

    /// Everything live, highest priority first, with the one the person chose in the peek (while Choose the Activity is on and it is
    /// still live) moved up to lead, behind an alert. The island shows the top two.
    var compactActivities: [CompactActivity] {
        var live = liveActivities
        if let lead = previewLead {
            // The Settings preview picks what shows, whether or not Choose the Activity is on.
            let standing = live.filter { !$0.isChoosable }
            switch lead {
            case .idle: return standing
            case .activity(let id):
                guard let chosen = live.first(where: { $0.choiceID == id && $0.isChoosable }) else { return standing }
                live.removeAll { $0.choiceID == id }
                return standing + [chosen] + live.filter(\.isChoosable)
            }
        }
        guard features.settings.isOn(.chooseActivity), let chosen = chosenActivityID,
            let index = live.firstIndex(where: { $0.choiceID == chosen && $0.isChoosable })
        else { return live }
        var list = live
        let front = list.first?.isChoosable == false ? 1 : 0
        guard index > front else { return live }
        list.insert(list.remove(at: index), at: front)
        return list
    }

    /// Everything live in the order DESIGN gives: banner, alert, recording, microphone, the clocks, a countdown, work,
    /// a transfer, music, an agent.
    var liveActivities: [CompactActivity] {
        if let banner { return [.banner(banner)] }
        var list: [CompactActivity] = []
        if !levels.isEmpty { list.append(.levels(levels)) }
        if let alert { list.append(.alert(alert)) }
        if features.screenRecorder.isRecording { list.append(.recording(.screen)) }
        if features.voice.isRecording { list.append(.recording(.voice)) }
        // MacIsland's own voice note is already shown as a recording, not as another app on the microphone.
        let recordingItself = features.voice.isRecording && features.privacy.microphoneAppBundleID == nil
        if features.privacy.isMicrophoneInUse, !recordingItself { list.append(.microphone) }
        let clockIsOn = features.settings.isOn(.clock)
        if clockIsOn, features.timer.isActive { list.append(.timer) }
        if clockIsOn, features.pomodoro.isActive { list.append(.pomodoro) }
        if clockIsOn, features.stopwatch.isActive { list.append(.stopwatch) }
        if let event = activeCountdown { list.append(.countdown(event)) }
        if let job = features.work.current { list.append(.working(job.title)) }
        if !features.transfers.transfers.isEmpty { list.append(.transfer) }
        if features.settings.showsMusicCompact, features.settings.isOn(.music), features.nowPlaying.state.hasMedia {
            list.append(.media)
        }
        // Music outranks a running agent: an agent can run for an hour, and the song is what is being listened to.
        if features.settings.isOn(.agents), features.settings.showsAgentCompact, !features.agents.liveTasks.isEmpty {
            list.append(.agent)
        }
        if features.settings.isOn(.tools), features.settings.showsKeepAwakeCompact, features.keepAwake.isOn,
            features.keepAwake.endsAt != nil
        {
            list.append(.keepAwake)
        }
        return list
    }

    /// The event the closed island counts down to: within the hour before it starts, and chosen (or every event, if that is on). Needs
    /// Calendar to be on.
    var activeCountdown: AgendaItem? {
        guard features.settings.isOn(.calendar) else { return nil }
        let settings = features.settings
        var items = features.agenda.upcoming
        if let next = features.agenda.next, !items.contains(where: { $0.id == next.id }) { items.append(next) }
        return AgendaRules.countdown(
            in: items, now: Date(), all: settings.countsDownToEveryEvent, chosen: Set(settings.countdowns.keys))
    }

    /// The top activity.
    var compactActivity: CompactActivity { compactActivities.first ?? .none }

    /// What a peek is about: the top activity, leaving out the level HUD, which an open island draws in its own band.
    var peekActivity: CompactActivity {
        compactActivities.first { if case .levels = $0 { false } else { true } } ?? .none
    }

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
            rightTabs: features.settings.shownRightTabs.count,
            hasStatus: hasStatusIndicators,
            hasWeather: features.weather.conditions != nil && features.settings.isOn(.weather),
            hasNotesTab: features.settings.shownTabs.contains(.notes)
        )
    }

    /// The New Note pencil, when there is room and Notes isn't already a tab.
    var showsStripPencil: Bool { trailingStripPlan.pencil && features.settings.isShown(.notes) }

    /// The weather, whenever it fits beside the tab, the status, and Settings: it must never crowd the notch.
    var showsStripWeather: Bool { trailingStripPlan.weather }

    /// Two activities as a minimal pair: leading is the top rank, trailing the second. An alert
    /// always stands alone, since its text is the message.
    var compactPair: (leading: CompactActivity, trailing: CompactActivity)? {
        let list = compactActivities
        guard list.count >= 2 else { return nil }
        if case .alert = list[0] { return nil }
        if case .levels = list[0] { return nil }
        return (list[0], list[1])
    }

    /// Width added on each side of the notch. Equal on both sides, except for the level HUD, which is a glyph and a bar when one level
    /// shows and a bar on each side when both do.
    private var compactSideWidths: (leading: CGFloat, trailing: CGFloat) {
        if presentation == .compact, case .levels(let hud) = compactActivity {
            if hud.isBoth { return (Theme.Metrics.levelSideWidth, Theme.Metrics.levelSideWidth) }
            return (Theme.Metrics.volumeHUDLeading, Theme.Metrics.volumeHUDTrailing)
        }
        return (compactSideWidth, compactSideWidth)
    }

    /// How far the island sits right of the notch's center, so uneven sides still hug the notch.
    var horizontalOffset: CGFloat {
        guard presentation == .compact, !showsDragTarget else { return 0 }
        let sides = compactSideWidths
        return (sides.trailing - sides.leading) / 2
    }

    private var compactSideWidth: CGFloat {
        if compactPair != nil { return geometry.notchSize.height + 8 }
        switch compactActivity {
        case .banner, .none: return 0
        case .alert, .levels: return 64
        case .microphone: return 60
        case .timer, .pomodoro, .stopwatch, .countdown, .transfer: return 52
        case .working, .recording, .agent: return 64
        case .media, .keepAwake: return geometry.notchSize.height + 8
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
    /// It is also not drawn while Hide in Full Screen has the front app on the whole display, nor, with Hide Until You Point at It, while
    /// the pointer is away (a banner or an alert still shows).
    var isPillHidden: Bool {
        guard presentation == .compact, !showsDragTarget else { return false }
        if !geometry.hasNotch, compactActivity == .none { return true }
        if hidesForFullScreen { return true }
        return features.settings.hidesUntilPointer && !isHovering && alert == nil
    }

    // MARK: Full screen

    /// The app in front covers the whole island display. Set by the app while Hide in Full Screen is on.
    private(set) var isFullScreen = false
    /// An alert that stays until seen, held back while the display is full screen, shown when it ends.
    private var waitingAlert: IslandAlert?

    /// Whether the island is keeping out of the way of a full-screen app.
    var hidesForFullScreen: Bool { isFullScreen && features.settings.hidesInFullScreen }

    func setFullScreen(_ on: Bool) {
        guard on != isFullScreen else { return }
        isFullScreen = on
        if on {
            hoverTask?.cancel()
            if isSwelling { isSwelling = false }
            if state == .peek { state = .compact }
        } else if let waiting = waitingAlert {
            waitingAlert = nil
            flash(waiting, respectingFocus: false)
        }
    }

    /// Clock for a running timer or stopwatch, Now Playing for music, and the day at a glance when idle.
    var peekContentHeight: CGFloat {
        let choice = showsActivityChoice ? Theme.Metrics.hitTarget + Theme.Metrics.rowSpacing : 0
        return choice + activityPeekHeight
    }

    /// The height of the top activity's own peek.
    private var activityPeekHeight: CGFloat {
        switch peekActivity {
        case .timer, .pomodoro, .stopwatch, .countdown: Theme.Metrics.glanceHeight
        case .media: mediaContentHeight(peek: true)
        case .recording: Theme.Metrics.glanceHeight
        case .agent: Theme.Metrics.glanceHeight
        default: Theme.Metrics.idlePeekHeight
        }
    }

    /// The music player: the art, the scrubber, and the transport, a few points apart, and the lyric line when there is one. The
    /// Media tab has bigger art and sits a little lower than the peek. With nothing playing it is a single line.
    func mediaContentHeight(peek: Bool) -> CGFloat {
        let gap = Theme.Metrics.playerSpacing
        // The Mixer: with nothing playing in Now Playing but apps making sound, its panel stands alone; otherwise it replaces the
        // scrubber, lyric line, and transport while the Audio Output button has it open.
        if !peek, isMixerOn {
            if !features.nowPlaying.state.hasMedia {
                if showsMixerAlone {
                    return Theme.Metrics.outputRowHeight + gap + mixerBodyHeight
                }
            } else if showsMediaOutputs {
                return Theme.Metrics.playerTopInset + Theme.Metrics.playerArtwork + gap + Theme.Metrics.playerScrubber + gap
                    + Theme.Metrics.playerTransport + gap + mixerBodyHeight
            }
        }
        guard features.nowPlaying.state.hasMedia else { return Theme.Metrics.glanceHeight }
        let art = peek ? Theme.Metrics.playerPeekArtwork : Theme.Metrics.playerArtwork
        let inset = peek ? 0 : Theme.Metrics.playerTopInset
        let showsList = peek && showsPeekOutputList
        let lyrics = !showsList && !features.nowPlaying.lyrics.lines.isEmpty ? Theme.Metrics.lyricsRowHeight : 0
        let controlsHeight = showsList ? mediaOutputListHeight : Theme.Metrics.playerTransport
        let rowHeight = peek ? Theme.Metrics.outputRowHeight : Theme.Metrics.playerScrubber
        return inset + art + gap + rowHeight + gap + controlsHeight + lyrics
    }

    var mediaOutputListHeight: CGFloat {
        Self.outputListHeight(
            connectedCount: features.outputs.devices.count,
            disconnectedCount: features.bluetooth.notConnected.count)
    }

    static func outputListHeight(connectedCount: Int, disconnectedCount: Int) -> CGFloat {
        let rows = min(max(connectedCount + disconnectedCount, 1), Theme.Metrics.peekOutputMaxRows)
        return CGFloat(rows) * Theme.Metrics.outputRowHeight
            + (disconnectedCount == 0 ? 0 : Theme.Metrics.outputCaptionHeight)
    }

    // MARK: The Mixer's panel

    var isMixerOn: Bool { features.settings.isOn(.mixer) }

    func toggleMediaOutputs() {
        if !showsMediaOutputs { features.bluetooth.refresh() }
        withAnimation(Theme.Motion.resize) { showsMediaOutputs.toggle() }
    }

    /// The Media tab shows the Mixer's panel alone: Now Playing has nothing, but apps are making sound.
    var showsMixerAlone: Bool {
        isMixerOn && !features.nowPlaying.state.hasMedia && !features.mixer.rows.isEmpty
    }

    /// What is under the panel's output row: one line for a message or for nothing playing, else a row per app, up to the cap.
    var mixerBodyHeight: CGFloat {
        let rows = features.mixer.access == .notAsked || features.mixer.access == .denied ? 1 : features.mixer.rows.count
        return CGFloat(min(max(rows, 1), Theme.Metrics.mixerMaxRows)) * Theme.Metrics.mixerRowHeight
    }

    var showsDragTarget: Bool { isFileDragActive && presentation == .compact }

    func setFileDragActive(_ active: Bool) {
        // With "Do Nothing", the island stays as it is while a file is dragged.
        let active = active && features.settings.effectiveDragTarget != .nothing
        guard active != isFileDragActive else { return }
        withAnimation(Theme.Motion.track) { isFileDragActive = active }
    }

    /// Height of the selected module below the notch.
    var currentContentHeight: CGFloat { contentHeight(for: selectedTab) }

    func contentHeight(for tab: IslandModule) -> CGFloat {
        switch tab {
        case .home:
            calendarExpanded
                ? Theme.Metrics.homeMonthHeight
                : homeLayout.contentHeight(catalog: features.settings.widgetDescriptor(for:))
        case .media: mediaContentHeight(peek: false)
        case .shelf: Theme.Metrics.shelfHeight
        case .clock:
            switch clockMode {
            case .timer: features.timer.isActive ? Theme.Metrics.clockRing : Theme.Metrics.timerSetter
            case .stopwatch: Theme.Metrics.clockRing
            case .pomodoro: Theme.Metrics.clockRing + Theme.Metrics.pomodoroStatsHeight
            }
        case .tools:
            features.mirror.isOn
                ? Theme.Metrics.mirrorHeight
                : (toolsExpanded ? Theme.Metrics.toolsGridHeight : Theme.Metrics.toolsRowHeight)
                    + (features.ringLight.isOn ? Theme.Metrics.ringLightControlsHeight : 0)
                    + (features.keepAwake.isOn ? Theme.Metrics.keepAwakeChipsHeight : 0)
        case .notes: Theme.Metrics.notesHeight
        case .reminders: Theme.Metrics.remindersHeight
        case .agents: agentsMode == .stats ? Theme.Metrics.agentsStatsHeight : Theme.Metrics.agentsHeight
        }
    }

    var size: CGSize {
        switch presentation {
        case .compact:
            if isPillHidden { return .zero }
            var size = geometry.compactSize
            let sides = compactSideWidths
            size.width += sides.leading + sides.trailing
            size.height += 1
            if showsDragTarget {
                size.width = max(size.width, geometry.compactSize.width + 2 * Theme.Metrics.dragTargetInset)
                size.height += Theme.Metrics.dragTargetHeight
            }
            return size
        case .banner:
            return CGSize(
                width: banner?.isAlert == true ? Theme.Metrics.bannerAlertWidth : Theme.Metrics.bannerWidth,
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

    /// How large the island counts as being under the pointer. A pill that is not drawn still has its hover zone.
    var hitSize: CGSize { isPillHidden ? geometry.compactSize : size }

    /// Area that counts as "over the island", in screen coordinates.
    var hitRect: CGRect { geometry.islandRect(for: hitSize).offsetBy(dx: horizontalOffset, dy: 0) }

    var showsOutputSatellites: Bool {
        presentation == .expanded && selectedTab == .media && showsMediaOutputs
    }

    var outputSatelliteLimit: Int {
        let availableHeight = Theme.Metrics.panelHeight - geometry.notchSize.height
            - Theme.Metrics.contentTopGap - Theme.Metrics.margin
        return max(Int(availableHeight / (Theme.Metrics.outputSatelliteSize + Theme.Metrics.outputSatelliteSpacing)), 0)
    }

    var outputSatellitesRect: CGRect? {
        let available = features.outputs.otherDevices.count + features.bluetooth.notConnected.count
        let count = min(available, outputSatelliteLimit)
        guard showsOutputSatellites, count > 0 else { return nil }
        let metrics = Theme.Metrics.self
        let height = CGFloat(count) * metrics.outputSatelliteSize + CGFloat(count - 1) * metrics.outputSatelliteSpacing
        let island = geometry.islandRect(for: size).offsetBy(dx: horizontalOffset, dy: 0)
        let top = geometry.screenFrame.maxY - geometry.notchSize.height - metrics.contentTopGap
        let width = metrics.outputSatelliteGap
            + (hoveredOutputSatelliteID == nil ? metrics.outputSatelliteSize : metrics.outputPillMaxWidth)
        return CGRect(x: island.maxX, y: top - height, width: width, height: height)
    }

    func isOverIsland(_ point: CGPoint) -> Bool {
        hitRect.contains(point) || (outputSatellitesRect?.contains(point) ?? false)
    }

    func setOutputSatelliteHover(_ id: String, hovering: Bool) {
        if hovering {
            hoveredOutputSatelliteID = id
        } else if id.isEmpty || hoveredOutputSatelliteID == id {
            hoveredOutputSatelliteID = nil
        }
    }

    func updateScrollArea(_ id: UUID, frame: CGRect?, axis: AxisLock.Axis) {
        guard let frame else {
            scrollAreas.removeValue(forKey: id)
            return
        }
        scrollAreas[id] = ScrollArea(frame: frame, axis: axis)
    }

    func scrollAxis(at point: CGPoint) -> AxisLock.Axis? {
        scrollAreas.values.first { $0.frame.contains(point) }?.axis
    }

    /// The timer is being set: the dial is on screen and takes horizontal scrolls.
    var isSettingTimer: Bool {
        presentation == .expanded && selectedTab == .clock && clockMode == .timer && !features.timer.isActive
    }

    /// Where the timer dial is on screen, with half a row gap of slack. Computed from the layout, not measured,
    /// so it has to follow `TimerSetter`. Nil unless a timer is being set.
    var timerDialRect: CGRect? {
        guard isSettingTimer else { return nil }
        let metrics = Theme.Metrics.self
        let top =
            geometry.screenFrame.maxY
            - (geometry.notchSize.height + metrics.contentTopGap + metrics.clockHeaderHeight + 10)
        let inset = ScreenGeometry.topFlare + metrics.margin
        let slop = metrics.rowSpacing / 2
        return CGRect(
            x: geometry.screenFrame.midX - metrics.expandedWidth / 2 + inset - slop,
            y: top - metrics.timerDial - slop,
            width: metrics.expandedWidth - 2 * inset + 2 * slop,
            height: metrics.timerDial + 2 * slop
        )
    }

    // MARK: The timer dial

    /// Starts scrubbing from the length now set.
    func beginDialScrub() {
        dialAnchor = Double(features.timer.durationMinutes)
        dialRaw = dialAnchor
        dialAtEnd = false
    }

    /// A drag: the ruler follows the pointer, from where the drag began.
    func scrubDial(translation: CGFloat) {
        if dialRaw == nil { beginDialScrub() }
        moveDial(toRaw: DialScrubber.position(anchor: dialAnchor, translation: translation))
    }

    /// A trackpad scroll: `dx` is finger movement since the last event, so fingers left pull higher minutes in.
    func scrubDial(byFingerDX dx: CGFloat) {
        if dialRaw == nil { beginDialScrub() }
        moveDial(toRaw: (dialRaw ?? dialAnchor) - Double(dx / Theme.Metrics.dialMinuteSpacing))
    }

    private func moveDial(toRaw raw: Double) {
        guard features.timer.phase == .idle else { return }
        dialRaw = raw
        let resolved = DialScrubber.resolve(raw)
        let before = features.timer.durationMinutes
        features.timer.setDuration(minutes: Int(resolved.clamped.rounded()))
        dialPosition = resolved.display
        dialOverscroll = resolved.overscroll
        let atEnd = resolved.overscroll > 0
        if atEnd, !dialAtEnd {
            dialHaptic(.generic)
        } else if !atEnd, features.timer.durationMinutes != before, features.timer.durationMinutes % 5 == 0 {
            dialHaptic(.alignment)
        }
        dialAtEnd = atEnd
    }

    /// The gesture is over: the ruler settles on the nearest minute.
    func endDialScrub() {
        guard dialRaw != nil else { return }
        dialRaw = nil
        dialAtEnd = false
        withAnimation(Theme.Motion.track) {
            dialPosition = nil
            dialOverscroll = 0
        }
    }

    /// A mouse wheel notch: one minute, and a tap at either end.
    func stepDial(_ step: Int) {
        let timer = features.timer
        guard timer.phase == .idle else { return }
        let target = timer.durationMinutes + step
        guard (TimerModel.minimumDialMinutes...TimerModel.maximumDialMinutes).contains(target) else {
            dialHaptic(.generic)
            return
        }
        withAnimation(Theme.Motion.track) { timer.setDuration(minutes: target) }
    }

    /// A tap on the ruler: that tick slides under the marker.
    func setDial(to minute: Int) {
        withAnimation(Theme.Motion.track) { features.timer.setDuration(minutes: minute) }
    }

    /// The compact play/pause control. Hovering it doesn't open the island, so it can be clicked.
    var compactControlRect: CGRect? {
        // A screen recording is one big stop button.
        if presentation == .compact, compactActivity == .recording(.screen), compactPair == nil { return hitRect }
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

    /// A feature was switched off: if the page on screen is its module, the island goes to Home.
    func leaveModuleThatIsOff() {
        // Without the Clipboard feature the Shelf has one mode.
        if shelfMode == .clipboard, !features.settings.isOn(.clipboard) { shelfMode = .files }
        if shelfMode == .downloads, !features.settings.isOn(.downloads) { shelfMode = .files }
        if selectedTab != .home, !features.settings.isShown(selectedTab) { select(.home) }
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

    /// Right-click a Home widget, Edit Home…: Settings opens on Home with that widget selected.
    func editHome(selecting id: UUID?) { onOpenSettings?(.home, id) }

    /// Opens the island on a module, whether or not it is one of the tabs.
    func show(_ module: IslandModule) {
        selectedTab = module
        open()
    }

    /// The names of the Shortcuts that exist, or nil until they have been listed. A Shortcut tool whose Shortcut isn't in it is dimmed.
    private(set) var installedShortcuts: Set<String>?
    /// The Shortcut tools that are running now.
    private(set) var runningShortcutTools: Set<UUID> = []
    /// Runs a Shortcut by name and says whether it finished, and lists them. Tests replace them.
    @ObservationIgnored var shortcutRunner: (String) async -> Bool = { await ShortcutsCLI.run(shortcut: $0) }
    @ObservationIgnored var shortcutLister: () async -> [String] = { await ShortcutsCLI.list() }

    /// Lists the Shortcuts again: when the Tools tab appears, and after a Shortcut tool is saved.
    func refreshInstalledShortcuts() {
        guard !features.settings.shortcutTools.isEmpty else { return }
        Task {
            let names = await shortcutLister()
            // An empty list is `shortcuts` failing to answer as often as it is a person with none; say nothing then.
            installedShortcuts = names.isEmpty ? nil : Set(names)
        }
    }

    /// Runs a tool made from a Shortcut: the blue working activity while it runs, a green alert when it finishes, and a red banner
    /// with the reason when it doesn't. A Shortcut that is no longer there says so, and offers to edit the tool.
    func runShortcutTool(_ tool: ShortcutTool) {
        guard !runningShortcutTools.contains(tool.id) else { return }
        if let installed = installedShortcuts, !installed.contains(tool.shortcut) {
            showBanner(
                IslandBanner(
                    systemImage: "questionmark.square.dashed", tint: Theme.Tint.attention,
                    title: "\u{201C}\(tool.shortcut)\u{201D} Isn\u{2019}t There",
                    detail: "It may have been renamed or deleted",
                    actions: [
                        .init(title: "Edit Tool") { [weak self] in self?.editShortcutTool(tool.id) }
                    ]),
                for: .seconds(8), respectingFocus: false)
            return
        }
        runningShortcutTools.insert(tool.id)
        let job = features.work.begin("Running")
        Task {
            let finished = await shortcutRunner(tool.shortcut)
            features.work.end(job)
            runningShortcutTools.remove(tool.id)
            if finished {
                flash(
                    IslandAlert(systemImage: "checkmark.circle.fill", tint: Theme.Tint.positive, text: "Done"),
                    respectingFocus: false)
            } else {
                showBanner(
                    IslandBanner(
                        systemImage: "square.2.layers.3d", tint: Theme.Tint.attention,
                        title: "\u{201C}\(tool.shortcut)\u{201D} Didn\u{2019}t Finish",
                        detail: "Open it in Shortcuts to see why"),
                    for: .seconds(6), respectingFocus: false)
            }
        }
    }

    /// Opens Settings on Content, on Tools, with this tool's sheet showing.
    func editShortcutTool(_ id: UUID) {
        features.settings.requestedShortcutToolEdit = id
        onOpenSettings?(.tabs, nil)
    }

    /// Runs one of the person's Shortcuts. It shows as work in progress while it runs.
    func runShortcut(_ name: String) {
        let job = features.work.begin("Running")
        Task {
            let finished = await shortcutRunner(name)
            features.work.end(job)
            if finished {
                flash(
                    IslandAlert(systemImage: "checkmark.circle.fill", tint: Theme.Tint.positive, text: "Done"),
                    respectingFocus: false)
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

    // MARK: Capture

    /// Shows the camera in the Tools tab. The island stays open for as long as the camera is on and working (the `.mirror` hold).
    func startMirror() {
        guard !features.mirror.isOn else { return }
        selectedTab = .tools
        open()
        Task {
            await self.features.mirror.toggle()
            // A camera that failed or was denied holds nothing: the normal rules return.
            self.resumeAfterHold()
        }
    }

    func stopMirror() {
        features.mirror.stop()
        resumeAfterHold()
    }

    func toggleMirror() {
        features.mirror.isOn ? stopMirror() : startMirror()
    }

    /// Stops a recording in progress; otherwise folds the island away and lets the person choose what to record.
    func toggleScreenRecording() {
        if features.screenRecorder.isRecording {
            stopScreenRecording()
            return
        }
        closePinned()
        pickRegion { [weak self] selection in
            guard let self else { return }
            switch selection {
            case .cancelled: break
            case .display: Task { await self.features.screenRecorder.start(region: nil) }
            case .region(let rect): Task { await self.features.screenRecorder.start(region: rect) }
            }
        }
    }

    func stopScreenRecording() {
        Task { await features.screenRecorder.stop() }
    }

    /// Starts or stops a voice note. A muted microphone would record silence, so it offers to unmute first.
    func toggleVoiceNote() {
        let voice = features.voice
        if voice.isRecording {
            Task { await voice.stop() }
            return
        }
        if features.micMute.isMuted {
            showBanner(
                IslandBanner(
                    systemImage: "mic.slash.fill",
                    tint: Theme.Tint.neutral,
                    title: "Mic Is Muted",
                    detail: "Unmute it to record a voice note",
                    actions: [
                        .init(title: "Unmute") { [weak self] in
                            self?.features.micMute.toggle()
                            Task { await voice.start() }
                        }
                    ]
                ),
                for: .seconds(8),
                respectingFocus: false
            )
            return
        }
        Task { await voice.start() }
    }

    /// Tapping the compact island opens it, except while recording the screen, where it stops.
    func tapCompact() {
        if compactActivity == .recording(.screen), compactPair == nil {
            stopScreenRecording()
        } else if compactActivity == .agent, compactPair == nil {
            show(.agents)
        } else {
            open()
        }
    }

    // MARK: Holds

    /// The holds in force: the ones taken by name, and `.mirror` for as long as the camera is on and working. A camera that
    /// failed (`isUnavailable`) or was denied holds nothing.
    var activeHolds: Set<IslandHold> {
        var all = holds
        let mirror = features.mirror
        if mirror.isOn, !mirror.isUnavailable, mirror.access != .denied { all.insert(.mirror) }
        return all
    }

    /// Something keeps the island open, so the pointer leaving does not fold it.
    var isHeld: Bool { !activeHolds.isEmpty }

    /// A hold that only its owner ends: a menu, Quick Look, a panel, Mirror.
    var isHeldHard: Bool { activeHolds.contains { !$0.endsWithPointer } }

    /// Whether a click outside the island closes it: it is pinned (by the keyboard or a text field), and nothing holds it open.
    var closesOnClickOutside: Bool {
        (isPinnedOpen || holds.contains(.textFocus)) && !isHeldHard
    }

    func hold(_ hold: IslandHold) {
        guard hold != .mirror else { return }
        hoverTask?.cancel()
        holds.insert(hold)
    }

    /// Lets go of a hold. When it was the last, the normal rules return.
    func release(_ hold: IslandHold) {
        guard holds.remove(hold) != nil else { return }
        resumeAfterHold()
    }

    /// Holds the island open while `body` runs, for a panel that is shown and answered (a save panel).
    func holding<T>(_ hold: IslandHold, during body: () async -> T) async -> T {
        self.hold(hold)
        defer { release(hold) }
        return await body()
    }

    /// With the last hold gone, an island the pointer is not over folds after the usual delay, from now, not never.
    private func resumeAfterHold() {
        guard !isHeld, !isPinnedOpen, state != .compact, banner == nil else { return }
        let inside = hitRect.contains(pointerLocation())
        isHovering = inside
        hoverTask?.cancel()
        if !inside { scheduleClose() }
    }

    private func scheduleClose() {
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Timing.closeDelay)
            guard !Task.isCancelled, let self, self.state != .compact, !self.isHeld else { return }
            withAnimation(Theme.Motion.close) { self.state = .compact }
        }
    }

    func copySnippet(_ snippet: Snippet) {
        features.clipboard.copyText(snippet.text)
        flash(
            IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
            respectingFocus: false)
    }

    func setCalendarExpanded(_ expanded: Bool) {
        if !expanded { calendarSelectedDay = nil }
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
                        actions: [.init(title: "Allow Access") { AgendaMonitor.openRemindersSettings() }]
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

    func setAgentsMode(_ mode: AgentsMode) {
        guard mode != agentsMode else { return }
        withAnimation(Theme.Motion.resize) { agentsMode = mode }
    }

    func setStatsAgent(_ agent: AgentKind?) {
        statsFilter = StatsFilter(agent: agent)
    }

    func setStatsRange(_ range: StatsRange) {
        guard range != statsRange else { return }
        statsRange = range
    }

    func setUsageRange(_ range: UsageRange) {
        guard range != usageRange else { return }
        usageRange = range
    }

    func setShelfMode(_ mode: ShelfMode) {
        guard mode != .clipboard || features.settings.isOn(.clipboard) else { return }
        guard mode != .downloads || features.settings.isOn(.downloads) else { return }
        withAnimation(Theme.Motion.resize) { shelfMode = mode }
        features.settings.shelfMode = mode
    }

    func setHoveredShelfItem(_ url: URL?) {
        hoveredShelfItem = url
        if url != nil { onWantsKeyboard?() }
    }

    /// Quick Look for a Shelf file. The island stays open while the preview is up.
    func showQuickLook(_ url: URL) {
        NSApp.activate()
        quickLookURL = url
    }

    // MARK: Shelf results

    func addResultToShelf(_ result: ShelfResult) {
        withAnimation(Theme.Motion.resize) { _ = features.fileTools.addToShelf(result) }
    }

    func replaceWithResult(_ result: ShelfResult) {
        withAnimation(Theme.Motion.resize) { _ = features.fileTools.replaceInShelf(result) }
    }

    /// The save panel is the island's own: it stays open behind it (the `.panel` hold), and the choice waits if the panel is cancelled.
    func saveResultToFolder(_ result: ShelfResult) {
        Task { _ = await holding(.panel) { await features.fileTools.saveToFolder(result) } }
    }

    func discardResult(_ result: ShelfResult) {
        withAnimation(Theme.Motion.resize) { features.fileTools.discard(result) }
    }

    /// Space over a Shelf file. Returns `false` when there is nothing to preview, so the key passes on.
    func quickLookHoveredItem() -> Bool {
        guard state == .expanded, selectedTab == .shelf, let url = hoveredShelfItem,
            shelfMode == .files ? features.shelf.items.contains(url) : shownDownloadURLs.contains(url)
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
            flash(
                IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
                respectingFocus: false)
        }
    }

    /// Puts a text card back on the pasteboard as plain text only (no other types).
    func copyPlainText(_ entry: ClipboardEntry) {
        guard case .text(let text) = entry.content else { return }
        features.clipboard.copyText(text)
        flash(
            IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
            respectingFocus: false)
    }

    /// Keeps a text card as a snippet in Notes.
    func saveAsSnippet(_ entry: ClipboardEntry) {
        guard case .text(let text) = entry.content else { return }
        features.notes.saveSnippet(text: text)
        flash(
            IslandAlert(systemImage: "text.badge.plus", tint: Theme.Tint.positive, text: "Saved"),
            respectingFocus: false)
    }

    // MARK: Clipboard search and paste

    /// What is typed in the Shelf's Clipboard search. Cleared when the Shelf goes.
    var clipboardQuery = ""
    /// ⌘ is down while the clipboard shows: its first nine cards show their keys.
    var isCommandHeld = false
    /// Where a copy goes back to. The general pasteboard; a test gives it a private one.
    @ObservationIgnored var pasteboard: NSPasteboard = .general
    @ObservationIgnored var paster: Pasting = LivePaster()
    /// A moment for the app that had the keyboard to take it back before ⌘V is pressed.
    @ObservationIgnored var pasteDelay: Duration = .milliseconds(50)
    /// Lets go of the keyboard so the app behind the island has it again. Set by the app.
    @ObservationIgnored var onReleaseKeyboard: (() -> Void)?
    @ObservationIgnored private(set) var pasteTask: Task<Void, Never>?

    /// The copies that match what is typed, newest first.
    var shownClipboardEntries: [ClipboardEntry] { features.clipboard.matches(clipboardQuery) }

    /// The Shelf is open on its Downloads, which is the only time the folder is watched.
    var isDownloadsShowing: Bool {
        state == .expanded && selectedTab == .shelf && shelfMode == .downloads && features.settings.isOn(.downloads)
    }

    /// The files Quick Look can step through in Downloads.
    var shownDownloadURLs: [URL] {
        shelfMode == .downloads ? features.downloads.items.filter { !$0.isArriving }.map(\.url) : []
    }

    /// The Shelf is open on its Clipboard, which is where the paste keys work.
    var isClipboardShowing: Bool {
        state == .expanded && selectedTab == .shelf && shelfMode == .clipboard && features.settings.isOn(.clipboard)
    }

    /// Puts the copy back on the pasteboard, folds the island, gives the keyboard back, and presses ⌘V in the app that has it. Without
    /// Accessibility it only copies, and says so, as clicking a card does.
    func pasteClipboardEntry(_ entry: ClipboardEntry) {
        guard paster.canPaste else {
            copyFromClipboardHistory(entry)
            return
        }
        features.clipboard.copy(entry, to: pasteboard)
        clipboardQuery = ""
        closePinned()
        onReleaseKeyboard?()
        let paster = paster
        let delay = pasteDelay
        pasteTask?.cancel()
        pasteTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            _ = paster.paste()
        }
    }

    /// ⌘1 to ⌘9: paste the nth copy shown. False (so the key goes on) when the clipboard isn't showing or has no such copy.
    func pasteClipboardShortcut(_ digit: Int) -> Bool {
        let entries = shownClipboardEntries
        guard isClipboardShowing, (1...9).contains(digit), digit <= entries.count else { return false }
        pasteClipboardEntry(entries[digit - 1])
        return true
    }

    /// Return: paste the first copy shown.
    func pasteFirstClipboardMatch() -> Bool {
        guard isClipboardShowing, let first = shownClipboardEntries.first else { return false }
        pasteClipboardEntry(first)
        return true
    }

    /// Esc takes back one thing before it closes the island, innermost first: the clipboard search, the Mixer's panel, the Tools grid, a
    /// day picked in the month, then the month. True when it did.
    func stepBack() -> Bool {
        if !clipboardQuery.isEmpty {
            clipboardQuery = ""
            return true
        }
        if showsMediaOutputs, selectedTab == .media {
            withAnimation(Theme.Motion.resize) { showsMediaOutputs = false }
            return true
        }
        // Mirror stays until Done, so the grid behind it is not a step.
        if toolsExpanded, selectedTab == .tools, !features.mirror.isOn {
            setToolsExpanded(false)
            return true
        }
        if calendarSelectedDay != nil {
            calendarSelectedDay = nil
            return true
        }
        if calendarExpanded, selectedTab == .home {
            setCalendarExpanded(false)
            return true
        }
        return false
    }

    func copyFromClipboardHistory(_ entry: ClipboardEntry) {
        features.clipboard.copy(entry, to: pasteboard)
        flash(
            IslandAlert(systemImage: "doc.on.clipboard.fill", tint: Theme.Tint.neutral, text: "Copied"),
            respectingFocus: false)
    }

    func setClockMode(_ mode: ClockMode) {
        withAnimation(Theme.Motion.resize) { clockMode = mode }
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        hoverTask?.cancel()

        // The level HUD holds still while the pointer is on it, then leaves as it would have.
        if !levels.isEmpty {
            if hovering {
                volumeTask?.cancel()
                brightnessTask?.cancel()
            } else {
                if levels.volume != nil { scheduleLevelExpiry(.volume) }
                if levels.brightness != nil { scheduleLevelExpiry(.brightness) }
            }
        }

        // A banner holds still while the pointer is on it, then leaves shortly after.
        if banner != nil {
            if hovering {
                bannerTask?.cancel()
            } else {
                scheduleBannerDismissal(after: .seconds(1.5))
            }
            return
        }

        // The pointer takes over from the keyboard and a text field; leaving doesn't close a pinned or held island.
        if hovering {
            isPinnedOpen = false
            holds.remove(.textFocus)
        }
        if isPinnedOpen || isHeld { return }

        if hovering {
            guard state == .compact, !hidesForFullScreen else { return }
            if !isPillHidden { withAnimation(Theme.Motion.track) { isSwelling = true } }
            // With Peek on Hover off, hovering only swells it: a click or a swipe opens it.
            guard features.settings.peeksOnHover else { return }
            let dwell = features.settings.peekDelay.duration
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: dwell)
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
            scheduleClose()
        }
    }

    /// Opening the island counts as seeing an alert that stays until seen.
    private func revealPendingAlert() {
        guard let alert, alert.staysUntilSeen else { return }
        if let tab = alert.opensTab { selectedTab = tab }
        self.alert = nil
    }

    /// Click, swipe down, or the shortcut: the full island with tabs. Opening from closed goes to the page Open On chose, unless the
    /// caller already picked one; an alert's own page still wins.
    func open(applyingOpenOn: Bool = true) {
        hoverTask?.cancel()
        bannerTask?.cancel()
        let bannerTab = banner?.opensTab
        withAnimation(Theme.Motion.open) {
            isSwelling = false
            banner = nil
            if applyingOpenOn, state != .expanded { applyOpenOn() }
            revealPendingAlert()
            if let bannerTab { selectedTab = bannerTab }
            state = .expanded
        }
    }

    /// The page the island opens on from closed: the last one, Home, or the page of what is live.
    private func applyOpenOn() {
        switch features.settings.openOn {
        case .lastTab:
            return
        case .home:
            selectedTab = .home
        case .live:
            guard let module = Self.module(for: compactActivity), features.settings.isOn(.shelf) || module != .shelf,
                module.isAvailable, Feature.module(for: module).map(features.settings.isOn) ?? true
            else { return }
            selectedTab = module
            if module == .shelf, features.settings.isOn(.downloads) { shelfMode = .downloads }
        }
    }

    /// Where an activity lives: a clock's is Clock, music's Media, a download's the Shelf, an agent's Agents, a countdown's Home. The
    /// rest have no page of their own.
    static func module(for activity: CompactActivity) -> IslandModule? {
        switch activity {
        case .timer, .pomodoro, .stopwatch: .clock
        case .media: .media
        case .transfer: .shelf
        case .agent: .agents
        case .countdown: .home
        case .banner, .alert, .levels, .recording, .microphone, .working, .keepAwake, .none: nil
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

    /// The Shelf's shortcut: open and pin the island on the Shelf, even when the Shelf isn't in the tab strip. Open on another tab, it
    /// moves to the Shelf; already on the Shelf, it closes.
    func toggleShelfFromKeyboard() {
        guard features.settings.isOn(.shelf) else { return }
        if state == .expanded {
            if selectedTab == .shelf {
                closePinned()
            } else {
                isPinnedOpen = true
                select(.shelf)
            }
            return
        }
        selectedTab = .shelf
        isPinnedOpen = true
        open(applyingOpenOn: false)
    }

    /// Esc, the shortcut, a swipe up, or a click outside a pinned island. Mirror is the one thing that refuses: it stays until
    /// Done. A menu or panel does not refuse Esc or the shortcut (a stuck hold must never trap the island open); a click outside
    /// is held off by them in `closesOnClickOutside`.
    func closePinned() {
        guard !activeHolds.contains(.mirror) else { return }
        isPinnedOpen = false
        holds.remove(.textFocus)
        hoverTask?.cancel()
        withAnimation(Theme.Motion.close) { state = .compact }
    }

    /// What a two-finger swipe on the island does: down opens, up closes, sideways changes the tab. One place for the real island's
    /// tracker and the first-run guide's stage, so they can't disagree. Nothing happens with swiping turned off in Settings.
    func perform(_ swipe: Swipe) {
        guard features.settings.swipesEnabled else { return }
        switch swipe {
        case .down where presentation != .expanded:
            open()
        case .up where presentation == .expanded:
            closePinned()
        case .left where presentation == .expanded:
            // The strip follows the fingers: swiping left moves toward the tab on the left.
            selectAdjacentTab(-1)
        case .right where presentation == .expanded:
            selectAdjacentTab(1)
        default:
            break
        }
    }

    /// Forgets a peek or a close that was waiting on the pointer, and a keyboard pin. For a view model whose state is set from outside
    /// (the Settings preview, the first-run guide's stage), so a late timer can't undo what was just shown.
    func resetPointerState() {
        hoverTask?.cancel()
        hoverTask = nil
        isPinnedOpen = false
        holds.removeAll()
        isSwelling = false
    }

    /// Left/right arrow: move to the neighboring tab, without wrapping.
    func selectAdjacentTab(_ step: Int) {
        // Changing tab would switch the camera off: with Mirror on, swiping and the arrow keys are ignored. Clicking a tab still works.
        guard !activeHolds.contains(.mirror) else { return }
        let tabs = visibleTabs()
        guard let index = tabs.firstIndex(of: selectedTab) else { return }
        let next = index + step
        guard tabs.indices.contains(next) else { return }
        select(tabs[next])
    }

    func visibleTabs() -> [IslandModule] { features.settings.shownTabs }
    func leftTabs() -> [IslandModule] { features.settings.shownLeftTabs }
    func rightTabs() -> [IslandModule] { features.settings.shownRightTabs }

    /// Puts away Shelf files that stayed longer than the person wants. Runs on launch and when the Shelf appears.
    func sweepShelf() {
        features.shelf.sweep(features.settings.shelfRetention)
    }

    func setDropTargeted(_ targeted: Bool) {
        guard targeted, features.settings.isOn(.shelf) else { return }
        hoverTask?.cancel()
        isHovering = true
        withAnimation(Theme.Motion.open) {
            selectedTab = .shelf
            shelfMode = .files
            state = .expanded
        }
    }

    /// While a Focus is on and the person asked for quiet, only alerts that stay until seen get through.
    private var isQuiet: Bool { features.settings.quietDuringFocus && features.focus.readNow() }

    /// `respectingFocus: false` is for feedback to something the person just did.
    func flash(
        _ alert: IslandAlert, for duration: Duration = .seconds(3), respectingFocus: Bool = true,
        event: AmbientEvent? = nil
    ) {
        if let event, features.settings.isMuted(event) { return }
        if respectingFocus, isQuiet, !alert.staysUntilSeen { return }
        // A full-screen app has the display: what passes is dropped, and what stays until seen waits for it to end.
        if hidesForFullScreen {
            if alert.staysUntilSeen { waitingAlert = alert }
            return
        }
        alertTask?.cancel()
        withAnimation(Theme.Motion.open) { self.alert = alert }
        guard !alert.staysUntilSeen else { return }
        scheduleAlertDismissal(after: duration)
    }

    private func scheduleAlertDismissal(after duration: Duration) {
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Theme.Motion.close) { self.alert = nil }
        }
    }

    // MARK: Volume and brightness HUD

    /// Whether the HUD may take the stage: nothing that needs the person is showing, and no full-screen app has the display. It shows in
    /// any state (the open island draws it in the band beside the notch). It is never queued behind an alert that stays until seen: the
    /// key goes to the system's own HUD instead.
    var canShowLevelHUD: Bool {
        banner == nil && alert?.staysUntilSeen != true && !hidesForFullScreen
    }

    /// Shows a level in the island for a moment. Each press shows it again, and the pointer on it holds it.
    func showLevel(_ reading: LevelReading) {
        switch reading {
        case .volume(let level): withAnimation(Theme.Motion.open) { levels.volume = level }
        case .brightness(let fraction): withAnimation(Theme.Motion.open) { levels.brightness = fraction }
        }
        scheduleLevelExpiry(reading.kind)
    }

    /// For the Settings preview only: holds the levels on the island, with no expiry, or clears them.
    func setPreviewLevels(volume: VolumeLevel?, brightness: Double?) {
        volumeTask?.cancel()
        brightnessTask?.cancel()
        let hud = LevelHUD(volume: volume, brightness: brightness)
        if levels != hud { withAnimation(Theme.Motion.open) { levels = hud } }
    }

    private func scheduleLevelExpiry(_ kind: LevelKind) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: Theme.Timing.levelHUD)
            guard !Task.isCancelled, let self else { return }
            withAnimation(Theme.Motion.resize) {
                switch kind {
                case .volume: self.levels.volume = nil
                case .brightness: self.levels.brightness = nil
                }
            }
        }
        switch kind {
        case .volume:
            volumeTask?.cancel()
            volumeTask = task
        case .brightness:
            brightnessTask?.cancel()
            brightnessTask = task
        }
    }

    /// Whether a banner for `event` would show right now: it isn't muted, no full-screen app has the display, and no Focus is holding
    /// banners. For a caller that has something to do first that it must not do for a banner that won't show.
    func canShowBanner(for event: AmbientEvent? = nil, respectingFocus: Bool = true) -> Bool {
        if let event, features.settings.isMuted(event) { return false }
        if hidesForFullScreen { return false }
        return !(respectingFocus && isQuiet)
    }

    /// Shows a banner, then optionally leaves `followUp` as a compact alert.
    func showBanner(
        _ banner: IslandBanner,
        for duration: Duration = .seconds(4),
        followUp: IslandAlert? = nil,
        respectingFocus: Bool = true,
        event: AmbientEvent? = nil
    ) {
        if let event, features.settings.isMuted(event) { return }
        if hidesForFullScreen { return }
        if respectingFocus, isQuiet {
            if let followUp { flash(followUp) }
            return
        }
        // A banner folds the island, which Mirror, a menu, or a panel must not lose: it waits as an alert until it is seen.
        if state != .compact, isHeldHard {
            flash(
                IslandAlert(systemImage: banner.systemImage, tint: banner.tint, text: banner.title, staysUntilSeen: true),
                respectingFocus: false)
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

    func performBannerAction(at index: Int = 0) {
        if let banner, banner.actions.indices.contains(index) { banner.actions[index].perform() }
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

    /// Takes a short alert off the island.
    func clearAlert() {
        alertTask?.cancel()
        withAnimation(Theme.Motion.close) { alert = nil }
    }

    func dismissBanner() {
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

    static func plan(available: CGFloat, rightTabs: Int, hasStatus: Bool, hasWeather: Bool, hasNotesTab: Bool = false)
        -> Plan
    {
        var used = settings + CGFloat(rightTabs) * (tab + spacing) + (hasStatus ? status + spacing : 0)
        let weatherFits = hasWeather && used + weather + spacing <= available
        if weatherFits { used += weather + spacing }
        let pencilFits = !hasNotesTab && used + pencil + spacing <= available
        return Plan(weather: weatherFits, pencil: pencilFits)
    }
}
