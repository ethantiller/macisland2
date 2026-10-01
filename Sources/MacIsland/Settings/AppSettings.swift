import Carbon.HIToolbox
import Observation

/// What a file dragged toward the island does.
enum DragTarget: String, CaseIterable, Identifiable {
    case shelfAndAirDrop, shelfOnly, airDropOnly, nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelfAndAirDrop: "Show Shelf and AirDrop"
        case .shelfOnly: "Show Shelf Only"
        case .airDropOnly: "Show AirDrop Only"
        case .nothing: "Do Nothing"
        }
    }
}

/// Which display carries the island.
enum IslandDisplay: String, CaseIterable, Identifiable {
    case builtIn, primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: "Built-in Display"
        case .primary: "Primary Display"
        }
    }
}

/// How many tools the Tools row shows before "More" (four, six, or all eight).
enum PinLimit: Int, CaseIterable, Identifiable {
    case four = 4
    case six = 6
    case eight = 8

    var id: Int { rawValue }
}

/// Personal choices only. Anything the design should just get right isn't a setting (see DESIGN.md).
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    /// Registers a global shortcut with the system, returning false when another app holds the key. Set by the app;
    /// without it (in tests) every valid shortcut is accepted.
    @ObservationIgnored var shortcutRegistrar: ((ShortcutSlot, KeyCombo?) -> Bool)?
    /// The display choice changed.
    @ObservationIgnored var onDisplayChange: (() -> Void)?
    @ObservationIgnored var onScreenshotsChange: (() -> Void)?
    @ObservationIgnored var onClipboardChange: (() -> Void)?
    /// Calendar or Reminders was turned on or off.
    @ObservationIgnored var onAgendaChange: (() -> Void)?
    /// Quiet in Focus was turned on or off.
    @ObservationIgnored var onQuietChange: (() -> Void)?
    /// The weather city was edited.
    @ObservationIgnored var onWeatherChange: (() -> Void)?
    /// Synced Lyrics was turned on or off.
    @ObservationIgnored var onLyricsChange: (() -> Void)?
    /// Replace the Volume HUD was turned on or off.
    @ObservationIgnored var onVolumeHUDChange: (() -> Void)?
    /// A feature was switched on or off, by any route (its own setting included). Set by the app.
    @ObservationIgnored var onFeatureChange: ((Feature) -> Void)?

    private(set) var launchAtLogin: Bool

    /// The keys that open the island from anywhere. Nil is off.
    private(set) var openShortcut: KeyCombo? {
        didSet {
            defaults.set(try? JSONEncoder().encode(StoredShortcut(combo: openShortcut)), forKey: Key.openShortcut)
        }
    }

    /// The keys that open the island on the Shelf from anywhere. Nil is off.
    private(set) var shelfShortcut: KeyCombo? {
        didSet {
            defaults.set(try? JSONEncoder().encode(StoredShortcut(combo: shelfShortcut)), forKey: Key.shelfShortcut)
        }
    }

    /// Hovering the compact island opens the peek after a moment. Off: hovering only swells it, and a click or a
    /// swipe opens it. For accidental peeks while reaching for the menu bar, and for a tremor.
    var peeksOnHover: Bool {
        didSet { defaults.set(peeksOnHover, forKey: Key.peeksOnHover) }
    }

    /// A two-finger swipe over the island opens it, closes it, and changes tabs. The timer dial's own scrubbing works
    /// either way.
    var swipesEnabled: Bool {
        didSet { defaults.set(swipesEnabled, forKey: Key.swipesEnabled) }
    }

    /// Which display carries the island: for a desk with the lid open and an external display as primary.
    var islandDisplay: IslandDisplay {
        didSet {
            defaults.set(islandDisplay.rawValue, forKey: Key.islandDisplay)
            onDisplayChange?()
        }
    }

    /// What a file dragged toward the island does: grow into a Shelf and AirDrop, Shelf-only, or AirDrop-only target, or nothing.
    var dragTarget: DragTarget {
        didSet { defaults.set(dragTarget.rawValue, forKey: Key.dragTarget) }
    }

    /// New screenshots land on the Shelf. Off also stops the Spotlight query that finds them.
    var addsScreenshots: Bool {
        didSet {
            defaults.set(addsScreenshots, forKey: Key.addsScreenshots)
            onScreenshotsChange?()
        }
    }

    var shelfRetention: ShelfRetention {
        didSet { defaults.set(shelfRetention.rawValue, forKey: Key.shelfRetention) }
    }

    /// How many copies the clipboard history keeps; 0 is off.
    var clipboardLimit: Int {
        didSet {
            defaults.set(clipboardLimit, forKey: Key.clipboardLimit)
            onClipboardChange?()
        }
    }

    /// The Shelf opens on the mode it was last left in. A dropped file always shows Files.
    var shelfMode: ShelfMode {
        didSet { defaults.set(shelfMode.rawValue, forKey: Key.shelfMode) }
    }

    /// The music beside the notch while the island is collapsed. Off: the Home widget and the Media tab stay.
    var showsMusicCompact: Bool {
        didSet { defaults.set(showsMusicCompact, forKey: Key.showsMusicCompact) }
    }

    /// Interruptions the person turned off.
    private(set) var mutedEvents: Set<AmbientEvent> {
        didSet { defaults.set(mutedEvents.map(\.rawValue).sorted(), forKey: Key.mutedEvents) }
    }

    /// Hold back banners and short alerts while a Focus is on.
    var quietDuringFocus: Bool {
        didSet {
            defaults.set(quietDuringFocus, forKey: Key.quiet)
            onQuietChange?()
        }
    }

    /// Off until turned on, so macOS only asks for access when the person wants it. This is the Calendar feature's switch.
    var showsCalendar: Bool {
        didSet {
            defaults.set(showsCalendar, forKey: Key.calendar)
            onAgendaChange?()
            if showsCalendar != oldValue { onFeatureChange?(.calendar) }
        }
    }

    var showsReminders: Bool {
        didSet {
            defaults.set(showsReminders, forKey: Key.reminders)
            onAgendaChange?()
        }
    }

    /// An event that is on now stays in Up Next until it ends, and reads how long it has left. Off, it leaves ten minutes after it starts.
    var showsTimeLeft: Bool {
        didSet {
            defaults.set(showsTimeLeft, forKey: Key.timeLeft)
            if showsTimeLeft != oldValue { onAgendaChange?() }
        }
    }

    /// Calendars left out of Up Next, the banner, and the month (their identifiers). Left out, not chosen, so a calendar added later
    /// counts until it is switched off. Identifiers belong to this Mac, so they are not in the settings file.
    private(set) var hiddenCalendars: Set<String> {
        didSet { defaults.set(hiddenCalendars.sorted(), forKey: Key.hiddenCalendars) }
    }

    /// A countdown beside the notch for every event with a start time, in the hour before it starts.
    var countsDownToEveryEvent: Bool {
        didSet { defaults.set(countsDownToEveryEvent, forKey: Key.countdownAll) }
    }

    /// The events the person chose to count down to: an event's id (its identifier and start) to when it ends. Pruned after it ends.
    /// Moving an event in Calendar changes its start, so its countdown is lost. Identifiers belong to this Mac, so not in the file.
    private(set) var countdowns: [String: Date] {
        didSet { defaults.set(countdowns.mapValues(\.timeIntervalSince1970), forKey: Key.countdowns) }
    }

    // MARK: AI Agents

    /// Which agents are read. At least one stays on.
    private(set) var readsClaudeCode: Bool {
        didSet { defaults.set(readsClaudeCode, forKey: Key.agentsClaude) }
    }

    private(set) var readsCodex: Bool {
        didSet { defaults.set(readsCodex, forKey: Key.agentsCodex) }
    }

    /// Reads an agent's logs? Does nothing unless it changes something, and refuses to turn off the last one.
    func setReads(_ agent: AgentKind, _ on: Bool) {
        switch agent {
        case .claudeCode:
            guard readsClaudeCode != on, on || readsCodex else { return }
            readsClaudeCode = on
        case .codex:
            guard readsCodex != on, on || readsClaudeCode else { return }
            readsCodex = on
        }
        onFeatureChange?(.agents)
    }

    func reads(_ agent: AgentKind) -> Bool { agent == .claudeCode ? readsClaudeCode : readsCodex }

    /// A working agent shows beside the notch while the island is closed.
    var showsAgentCompact: Bool {
        didSet { defaults.set(showsAgentCompact, forKey: Key.agentsCompact) }
    }

    /// The shortest task that gets a "Done" notice, in seconds.
    static let agentMinimums = [30, 60, 120, 300]
    var agentFinishMinimum: Int {
        didSet {
            if !Self.agentMinimums.contains(agentFinishMinimum) { agentFinishMinimum = 60; return }
            defaults.set(agentFinishMinimum, forKey: Key.agentsMinimum)
        }
    }

    /// The share of a plan limit at which the notice comes.
    static let agentThresholds = [75, 80, 90]
    var agentLimitThreshold: Int {
        didSet {
            if !Self.agentThresholds.contains(agentLimitThreshold) {
                agentLimitThreshold = 80
                defaults.set(80, forKey: Key.agentsThreshold)
                return
            }
            guard agentLimitThreshold != oldValue else { return }
            defaults.set(agentLimitThreshold, forKey: Key.agentsThreshold)
        }
    }

    /// Plan limits as the share that is left, not the share that is used.
    var showsLimitsLeft: Bool {
        didSet {
            guard showsLimitsLeft != oldValue else { return }
            defaults.set(showsLimitsLeft, forKey: Key.agentsLeft)
        }
    }

    func hasCountdown(_ id: String) -> Bool { countdowns[id] != nil }

    /// Adds or removes a countdown. Does nothing unless it changes something.
    func setCountdown(for item: AgendaItem, _ on: Bool) {
        if on {
            guard countdowns[item.id] == nil else { return }
            countdowns[item.id] = item.end ?? item.date
        } else {
            guard countdowns[item.id] != nil else { return }
            countdowns[item.id] = nil
        }
    }

    /// Forgets the countdowns of events that have ended.
    func pruneCountdowns(now: Date = Date()) {
        let kept = countdowns.filter { $0.value > now }
        if kept.count != countdowns.count { countdowns = kept }
    }

    func isCalendarHidden(_ id: String) -> Bool { hiddenCalendars.contains(id) }

    /// Does nothing unless it changes something.
    func setCalendarHidden(_ id: String, _ hidden: Bool) {
        guard hiddenCalendars.contains(id) != hidden else { return }
        if hidden { hiddenCalendars.insert(id) } else { hiddenCalendars.remove(id) }
        onAgendaChange?()
    }

    /// The charge level that raises the "fully charged" alert, from 80 to 100.
    var fullChargeLevel: Int {
        didSet {
            let clamped = min(max(fullChargeLevel, Self.fullChargeRange.lowerBound), Self.fullChargeRange.upperBound)
            if clamped != fullChargeLevel { fullChargeLevel = clamped; return }
            defaults.set(fullChargeLevel, forKey: Key.fullCharge)
        }
    }

    static let fullChargeRange = 80...100

    /// The Pomodoro's lengths, in minutes. A value outside its range is pulled back in.
    var pomodoroFocus: Int {
        didSet {
            // Assigning inside its own didSet doesn't run it again, so the pulled-in value is stored here.
            let clamped = Self.clamped(pomodoroFocus, to: PomodoroPlan.focusRange)
            if clamped != pomodoroFocus { pomodoroFocus = clamped }
            defaults.set(pomodoroFocus, forKey: Key.pomodoroFocus)
        }
    }

    var pomodoroShortBreak: Int {
        didSet {
            // Assigning inside its own didSet doesn't run it again, so the pulled-in value is stored here.
            let clamped = Self.clamped(pomodoroShortBreak, to: PomodoroPlan.shortBreakRange)
            if clamped != pomodoroShortBreak { pomodoroShortBreak = clamped }
            defaults.set(pomodoroShortBreak, forKey: Key.pomodoroShortBreak)
        }
    }

    var pomodoroLongBreak: Int {
        didSet {
            // Assigning inside its own didSet doesn't run it again, so the pulled-in value is stored here.
            let clamped = Self.clamped(pomodoroLongBreak, to: PomodoroPlan.longBreakRange)
            if clamped != pomodoroLongBreak { pomodoroLongBreak = clamped }
            defaults.set(pomodoroLongBreak, forKey: Key.pomodoroLongBreak)
        }
    }

    /// Focus sessions before the long break.
    var pomodoroSessions: Int {
        didSet {
            // Assigning inside its own didSet doesn't run it again, so the pulled-in value is stored here.
            let clamped = Self.clamped(pomodoroSessions, to: PomodoroPlan.sessionsRange)
            if clamped != pomodoroSessions { pomodoroSessions = clamped }
            defaults.set(pomodoroSessions, forKey: Key.pomodoroSessions)
        }
    }

    /// The four Pomodoro settings as the model reads them.
    var pomodoroPlan: PomodoroPlan {
        PomodoroPlan(
            focus: pomodoroFocus, shortBreak: pomodoroShortBreak, longBreak: pomodoroLongBreak,
            sessions: pomodoroSessions)
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// The city whose weather Home shows. Empty means no weather. Only the name is sent, to Open-Meteo.
    var weatherCity: String {
        didSet {
            defaults.set(weatherCity, forKey: Key.weatherCity)
            onWeatherChange?()
        }
    }

    /// Looks up synced lyrics on lrclib.net. On by default; the lookup sends the track's name, artist, album, and length.
    var showsLyrics: Bool {
        didSet {
            defaults.set(showsLyrics, forKey: Key.lyrics)
            onLyricsChange?()
        }
    }

    /// The island's volume HUD instead of the system's: MacIsland takes the volume keys, which needs Accessibility access, so it is off
    /// until turned on and stays off until that is granted.
    /// This is the Volume HUD feature's switch.
    var replacesVolumeHUD: Bool {
        didSet {
            defaults.set(replacesVolumeHUD, forKey: Key.volumeHUD)
            onVolumeHUDChange?()
            if replacesVolumeHUD != oldValue { onFeatureChange?(.volumeHUD) }
        }
    }

    /// The features the person switched on or off, by raw value. A feature that isn't here has its default, and `calendar` and
    /// `volumeHUD` are never here: their switches are `showsCalendar` and `replacesVolumeHUD`. Keys this build doesn't know (from a
    /// newer one) are kept.
    private(set) var featureChoices: [String: Bool] {
        didSet { defaults.set(featureChoices, forKey: Key.features) }
    }

    /// Home widgets that left because their feature went off, so they return when it comes back. A widget the person took off
    /// themselves isn't here: it stays off.
    private(set) var homeHiddenByFeature: [WidgetID] {
        didSet { defaults.set(homeHiddenByFeature.map(\.rawValue), forKey: Key.hiddenByFeature) }
    }

    var pinLimit: PinLimit {
        didSet { defaults.set(pinLimit.rawValue, forKey: Key.pinLimit) }
    }

    /// Tools in row order. Only the first `pinLimit` show; the rest wait behind More. May name a Shortcut tool that was since removed;
    /// `visiblePinned` leaves those out.
    private(set) var pinnedTools: [ToolID] {
        didSet { defaults.set(pinnedTools.map(\.rawValue), forKey: Key.pinned) }
    }

    /// Tools the person made from their Shortcuts, in the order they made them.
    private(set) var shortcutTools: [ShortcutTool] {
        didSet { defaults.set(try? JSONEncoder().encode(shortcutTools), forKey: Key.shortcutTools) }
    }

    /// The Tools tab has room for nine built-in tools, this many of the person's own, and Less: two rows of six.
    static let maxShortcutTools = 2

    /// A Shortcut tool the Tools tab's Settings asked to edit (its right-click menu). Not stored: the pane takes it.
    var requestedShortcutToolEdit: UUID?

    /// The tabs left of the notch, in order: up to `Theme.Metrics.maxTabs`.
    private(set) var leftTabs: [IslandModule] {
        didSet { defaults.set(leftTabs.map(\.rawValue), forKey: Key.leftTabs) }
    }

    /// The tabs right of the notch, in order: up to `Theme.Metrics.maxRightTabs`.
    private(set) var rightTabs: [IslandModule] {
        didSet { defaults.set(rightTabs.map(\.rawValue), forKey: Key.rightTabs) }
    }

    /// Modules the person put in the menu bar. None until they choose: the menu bar is theirs to fill.
    private(set) var menuBarModules: [IslandModule] {
        didSet { defaults.set(menuBarModules.map(\.rawValue), forKey: Key.menuBar) }
    }

    /// A Home widget the island asked Settings to select (right-click, Edit Home). Not stored: the editor takes it.
    var requestedHomeSelection: UUID?

    /// Widgets the person made, in the order they made them.
    private(set) var customWidgets: [CustomWidget] {
        didSet { defaults.set(try? JSONEncoder().encode(customWidgets), forKey: Key.customWidgets) }
    }

    /// What Home shows. Always normalized: what didn't fit is in `hidden`, and it is never empty.
    private(set) var homeLayout: HomeLayout {
        didSet { defaults.set(try? JSONEncoder().encode(homeLayout), forKey: Key.homeLayout) }
    }
    /// Arrangements the person saved, for the Presets menu. The built-in presets are code.
    private(set) var savedHomePresets: [SavedHomePreset] {
        didSet { defaults.set(try? JSONEncoder().encode(savedHomePresets), forKey: Key.savedHomePresets) }
    }

    /// Every tab, left to right. Never empty.
    var tabs: [IslandModule] { leftTabs + rightTabs }

    private enum Key {
        static let tabs = "tabs"
        static let leftTabs = "tabsLeft"
        static let menuBar = "menuBarModules"
        static let rightTabs = "tabsRight"
        static let hotkey = "hotkey"
        static let openShortcut = "shortcut.open"
        static let shelfShortcut = "shortcut.shelf"
        static let peeksOnHover = "peeksOnHover"
        static let swipesEnabled = "swipesEnabled"
        static let islandDisplay = "islandDisplay"
        static let mutedEvents = "mutedEvents"
        static let dragTarget = "dragTarget"
        static let addsScreenshots = "addsScreenshots"
        static let shelfRetention = "shelfRetention"
        static let clipboardLimit = "clipboardLimit"
        static let shelfMode = "shelfMode"
        static let showsMusicCompact = "showsMusicCompact"
        static let quiet = "quietDuringFocus"
        static let calendar = "showsCalendar"
        static let reminders = "showsReminders"
        static let pinLimit = "pinLimit"
        static let fullCharge = "fullChargeLevel"
        static let lyrics = "showsLyrics"
        static let volumeHUD = "replacesVolumeHUD"
        static let pomodoroFocus = "pomodoroFocus"
        static let pomodoroShortBreak = "pomodoroShortBreak"
        static let pomodoroLongBreak = "pomodoroLongBreak"
        static let pomodoroSessions = "pomodoroSessions"
        static let weatherCity = "weatherCity"
        static let pinned = "pinnedTools"
        static let shortcutTools = "tools.shortcuts"
        static let homeLayout = "home.layout"
        static let savedHomePresets = "home.savedPresets"
        static let customWidgets = "widgets.custom"
        static let features = "features.available"
        static let timeLeft = "agenda.timeLeft"
        static let hiddenCalendars = "agenda.hiddenCalendars"
        static let countdownAll = "agenda.countdownAll"
        static let countdowns = "agenda.countdowns"
        static let agentsClaude = "agents.claude"
        static let agentsCodex = "agents.codex"
        static let agentsCompact = "agents.compact"
        static let agentsMinimum = "agents.minimum"
        static let agentsThreshold = "agents.limitThreshold"
        static let agentsLeft = "agents.limitsLeft"
        static let hiddenByFeature = "home.hiddenByFeature"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = LaunchAtLogin.isEnabled
        openShortcut = Self.storedShortcut(defaults, Key.openShortcut) ?? Self.legacyOpenShortcut(defaults)
        shelfShortcut = Self.storedShortcut(defaults, Key.shelfShortcut) ?? .shelfDefault
        peeksOnHover = defaults.object(forKey: Key.peeksOnHover) as? Bool ?? true
        swipesEnabled = defaults.object(forKey: Key.swipesEnabled) as? Bool ?? true
        islandDisplay = defaults.string(forKey: Key.islandDisplay).flatMap(IslandDisplay.init) ?? .builtIn
        dragTarget = defaults.string(forKey: Key.dragTarget).flatMap(DragTarget.init) ?? .shelfAndAirDrop
        addsScreenshots = defaults.object(forKey: Key.addsScreenshots) as? Bool ?? true
        shelfRetention = defaults.string(forKey: Key.shelfRetention).flatMap(ShelfRetention.init) ?? .never
        var choices = Self.storedFeatureChoices(defaults)
        let storedLimit = defaults.object(forKey: Key.clipboardLimit) as? Int ?? ClipboardHistory.limit
        // The clipboard history used to be turned off with a limit of 0; that is the Clipboard feature now.
        if storedLimit == 0 {
            choices[Feature.clipboard.rawValue] = false
            defaults.set(choices, forKey: Key.features)
            defaults.set(ClipboardHistory.limit, forKey: Key.clipboardLimit)
        }
        featureChoices = choices
        let validLimit = ClipboardHistory.limits.contains(storedLimit) && storedLimit != 0
        clipboardLimit = validLimit ? storedLimit : ClipboardHistory.limit
        shelfMode = defaults.string(forKey: Key.shelfMode).flatMap(ShelfMode.init) ?? .files
        showsMusicCompact = defaults.object(forKey: Key.showsMusicCompact) as? Bool ?? true
        mutedEvents = Set((defaults.stringArray(forKey: Key.mutedEvents) ?? []).compactMap(AmbientEvent.init))
        quietDuringFocus = defaults.bool(forKey: Key.quiet)
        showsCalendar = defaults.bool(forKey: Key.calendar)
        showsReminders = defaults.bool(forKey: Key.reminders)
        showsTimeLeft = defaults.bool(forKey: Key.timeLeft)
        hiddenCalendars = Set(defaults.stringArray(forKey: Key.hiddenCalendars) ?? [])
        countsDownToEveryEvent = defaults.bool(forKey: Key.countdownAll)
        let storedClaude = defaults.object(forKey: Key.agentsClaude) as? Bool ?? true
        let storedCodex = defaults.object(forKey: Key.agentsCodex) as? Bool ?? true
        // At least one stays on: neither stored means a file edited by hand, and both are read.
        readsClaudeCode = storedClaude || !storedCodex
        readsCodex = storedCodex || !storedClaude
        showsAgentCompact = defaults.object(forKey: Key.agentsCompact) as? Bool ?? true
        let minimum = defaults.object(forKey: Key.agentsMinimum) as? Int ?? 60
        agentFinishMinimum = Self.agentMinimums.contains(minimum) ? minimum : 60
        let threshold = defaults.object(forKey: Key.agentsThreshold) as? Int ?? 80
        agentLimitThreshold = Self.agentThresholds.contains(threshold) ? threshold : 80
        showsLimitsLeft = defaults.object(forKey: Key.agentsLeft) as? Bool ?? false
        countdowns = (defaults.dictionary(forKey: Key.countdowns) as? [String: Double] ?? [:])
            .mapValues { Date(timeIntervalSince1970: $0) }
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? ""
        showsLyrics = defaults.object(forKey: Key.lyrics) as? Bool ?? true
        replacesVolumeHUD = defaults.bool(forKey: Key.volumeHUD)
        let storedFull = defaults.integer(forKey: Key.fullCharge)
        fullChargeLevel = Self.fullChargeRange.contains(storedFull) ? storedFull : 100
        // Absent (or 0) is never chosen: the default. A stored value outside its range is pulled in.
        func minutes(_ key: String, _ range: ClosedRange<Int>, default fallback: Int) -> Int {
            defaults.object(forKey: key) == nil ? fallback : Self.clamped(defaults.integer(forKey: key), to: range)
        }
        let plan = PomodoroPlan.default
        pomodoroFocus = minutes(Key.pomodoroFocus, PomodoroPlan.focusRange, default: plan.focus)
        pomodoroShortBreak = minutes(Key.pomodoroShortBreak, PomodoroPlan.shortBreakRange, default: plan.shortBreak)
        pomodoroLongBreak = minutes(Key.pomodoroLongBreak, PomodoroPlan.longBreakRange, default: plan.longBreak)
        pomodoroSessions = minutes(Key.pomodoroSessions, PomodoroPlan.sessionsRange, default: plan.sessions)
        pinLimit = PinLimit(rawValue: defaults.integer(forKey: Key.pinLimit)) ?? .six
        let shortcuts =
            defaults.data(forKey: Key.shortcutTools).flatMap { try? JSONDecoder().decode([ShortcutTool].self, from: $0) }
            ?? []
        shortcutTools = Array(shortcuts.filter(\.isValid).prefix(Self.maxShortcutTools))
        // A pinned Shortcut tool whose record is gone is dropped.
        pinnedTools =
            defaults.stringArray(forKey: Key.pinned)?.compactMap(ToolID.init)
            .filter { tool in tool.shortcutID.map { id in shortcuts.contains { $0.id == id } } ?? true }
            ?? ToolID.defaultPins
        menuBarModules = (defaults.stringArray(forKey: Key.menuBar) ?? []).compactMap(IslandModule.init).filter(
            \.isAvailable)
        let customs =
            defaults.data(forKey: Key.customWidgets).flatMap {
                try? JSONDecoder().decode([CustomWidget].self, from: $0)
            }
            ?? []
        customWidgets = customs.filter(\.isValid)
        // A layout that won't decode is shown as the default, and its bytes stay as they are until the next edit.
        homeLayout =
            defaults.data(forKey: Key.homeLayout).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) }
            .map { HomeLayout.normalized($0, catalog: { WidgetCatalog.descriptor(for: $0, customs: customs) }) }
            ?? .default
        homeHiddenByFeature = (defaults.stringArray(forKey: Key.hiddenByFeature) ?? []).compactMap(WidgetID.init)
        savedHomePresets =
            defaults.data(forKey: Key.savedHomePresets).flatMap {
                try? JSONDecoder().decode([SavedHomePreset].self, from: $0)
            }
            ?? []
        // The strip before it had two sides was one list; it becomes the left side. A strip nobody changed
        // follows the default to its new shape.
        func stored(_ key: String) -> [IslandModule]? {
            defaults.stringArray(forKey: key)?.compactMap(IslandModule.init)
        }
        let legacy = stored(Key.tabs)
        let left =
            stored(Key.leftTabs) ?? (legacy == IslandModule.previousDefaultTabs ? IslandModule.defaultTabs : legacy)
            ?? []
        (leftTabs, rightTabs) = Self.normalized(left: left, right: stored(Key.rightTabs) ?? [])
    }

    private static func storedFeatureChoices(_ defaults: UserDefaults) -> [String: Bool] {
        (defaults.dictionary(forKey: Key.features) ?? [:]).compactMapValues { $0 as? Bool }
    }

    /// A saved shortcut: `.some(nil)` is one turned off, and nil is one never chosen.
    private static func storedShortcut(_ defaults: UserDefaults, _ key: String) -> KeyCombo?? {
        guard let data = defaults.data(forKey: key),
            let stored = try? JSONDecoder().decode(StoredShortcut.self, from: data)
        else { return nil }
        return .some(stored.combo?.isValid == true ? stored.combo : nil)
    }

    /// The picker this replaced stored a name. It is read once, and from then on the new key is used.
    private static func legacyOpenShortcut(_ defaults: UserDefaults) -> KeyCombo? {
        switch defaults.string(forKey: Key.hotkey) {
        case "controlOptionI": .controlOptionI
        case "off": nil
        default: .openDefault
        }
    }

    // MARK: Shortcuts

    func shortcut(_ slot: ShortcutSlot) -> KeyCombo? {
        switch slot {
        case .open: openShortcut
        case .shelf: shelfShortcut
        }
    }

    /// The other slot that already has `combo`, if one does.
    func slot(holding combo: KeyCombo, besides slot: ShortcutSlot) -> ShortcutSlot? {
        ShortcutSlot.allCases.first { $0 != slot && shortcut($0) == combo }
    }

    /// Records a shortcut, or turns it off with nil. Refuses (false) one without Control, Option, or Command, one another
    /// slot already has, and one the system won't give this app because another app holds it. A refused shortcut leaves
    /// the old one in place. Does nothing unless it changes something.
    @discardableResult
    func setShortcut(_ slot: ShortcutSlot, _ combo: KeyCombo?) -> Bool {
        if let combo, !combo.isValid || self.slot(holding: combo, besides: slot) != nil { return false }
        guard combo != shortcut(slot) else { return true }
        guard shortcutRegistrar?(slot, combo) ?? true else { return false }
        switch slot {
        case .open: openShortcut = combo
        case .shelf: shelfShortcut = combo
        }
        return true
    }

    // MARK: Notifications

    func isMuted(_ event: AmbientEvent) -> Bool { mutedEvents.contains(event) }

    /// Does nothing unless it changes something (a binding may call it again with the same value).
    func setMuted(_ event: AmbientEvent, _ muted: Bool) {
        guard isMuted(event) != muted else { return }
        if muted { mutedEvents.insert(event) } else { mutedEvents.remove(event) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    /// The user may have changed Login Items in System Settings.
    func refresh() {
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: Restoring (used by `restore(_:)`, which lives with the archive)

    func replaceTabs(left: [IslandModule], right: [IslandModule]) {
        (leftTabs, rightTabs) = Self.normalized(left: left, right: right)
    }

    func replacePinned(_ tools: [ToolID]) { pinnedTools = tools }

    func clearHomeHiddenByFeature() {
        if !homeHiddenByFeature.isEmpty { homeHiddenByFeature = [] }
    }

    func replaceCustomWidgets(_ widgets: [CustomWidget]) { customWidgets = widgets }

    // MARK: Home

    /// Sets Home's layout, repaired to fit. Does nothing unless it changes something.
    func setHomeLayout(_ layout: HomeLayout) {
        let repaired = HomeLayout.normalized(layout, catalog: widgetDescriptor(for:))
        guard repaired != homeLayout else { return }
        homeLayout = repaired
    }

    /// Keeps the arrangement on Home under a name. Saving a name a saved layout has replaces it; a built-in preset's name is refused.
    @discardableResult
    func saveHomePreset(named raw: String) -> SavedHomePreset.SaveResult {
        let name = SavedHomePreset.cleaned(raw)
        guard !name.isEmpty else { return .empty }
        guard !SavedHomePreset.isBuiltIn(name) else { return .reserved }
        let layout = HomeLayout(widgets: homeLayout.widgets)
        if let index = savedHomePresets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            savedHomePresets[index].layout = layout
            return .replaced(savedHomePresets[index])
        }
        let preset = SavedHomePreset(name: name, layout: layout)
        savedHomePresets.append(preset)
        return .saved(preset)
    }

    /// Removes a saved layout, returning it and where it was so it can be put back.
    @discardableResult
    func deleteHomePreset(_ id: UUID) -> (preset: SavedHomePreset, index: Int)? {
        guard let index = savedHomePresets.firstIndex(where: { $0.id == id }) else { return nil }
        return (savedHomePresets.remove(at: index), index)
    }

    func restoreHomePreset(_ preset: SavedHomePreset, at index: Int) {
        guard !savedHomePresets.contains(where: { $0.id == preset.id }) else { return }
        savedHomePresets.insert(preset, at: min(max(index, 0), savedHomePresets.count))
    }

    /// Home's height with nothing else open: computed from the layout.
    var homeContentHeight: CGFloat { homeLayout.contentHeight(catalog: widgetDescriptor(for:)) }

    /// The descriptor for a widget this build knows, or one the person made.
    func widgetDescriptor(for id: WidgetID) -> WidgetDescriptor? {
        WidgetCatalog.descriptor(for: id, customs: customWidgets)
    }

    func customWidget(id: UUID) -> CustomWidget? { customWidgets.first { $0.id == id } }

    /// Adds a widget, or replaces the one with the same id. Refuses (false) one that isn't valid.
    @discardableResult
    func saveCustomWidget(_ widget: CustomWidget) -> Bool {
        guard widget.isValid else { return false }
        var widget = widget
        widget.title = widget.title.trimmingCharacters(in: .whitespaces)
        widget.maxAgeMinutes = max(widget.maxAgeMinutes, CustomWidget.minimumMaxAge)
        if let index = customWidgets.firstIndex(where: { $0.id == widget.id }) {
            guard customWidgets[index] != widget else { return true }
            customWidgets[index] = widget
        } else {
            customWidgets.append(widget)
        }
        // Its size may have changed, so the layout is fitted again.
        setHomeLayout(homeLayout)
        return true
    }

    /// Deletes a widget, and takes it off Home. This is the one place a widget is really removed.
    func removeCustomWidget(_ id: UUID) {
        guard customWidgets.contains(where: { $0.id == id }) else { return }
        var layout = homeLayout
        layout.widgets.removeAll { $0.widget == .custom(id) }
        layout.hidden.removeAll { $0.widget == .custom(id) }
        customWidgets.removeAll { $0.id == id }
        setHomeLayout(layout)
    }

    // MARK: Features

    /// Whether a feature is on. Two features keep the setting they always had: Calendar is `showsCalendar` and the Volume HUD is
    /// `replacesVolumeHUD`. The rest are in `featureChoices`, or have their default.
    func isOn(_ feature: Feature) -> Bool {
        switch feature {
        case .calendar: showsCalendar
        case .volumeHUD: replacesVolumeHUD
        default: featureChoices[feature.rawValue] ?? feature.isOnByDefault
        }
    }

    /// Does nothing unless it changes something (a binding may call it again with the same value). Whatever the feature gates
    /// keeps its settings; this only changes whether it shows and runs.
    func setOn(_ feature: Feature, _ on: Bool) {
        guard isOn(feature) != on else { return }
        switch feature {
        case .calendar: showsCalendar = on  // these two tell `onFeatureChange` themselves
        case .volumeHUD: replacesVolumeHUD = on
        default:
            featureChoices[feature.rawValue] = on
            syncHomeWidgets()
            onFeatureChange?(feature)
        }
    }

    /// Whether a widget may be on Home: its feature, if it has one, is on.
    func isWidgetAllowed(_ widget: WidgetID) -> Bool {
        WidgetCatalog.feature(of: widget).map(isOn) ?? true
    }

    /// Moves widgets between Home and Add Widgets to match the features: those whose feature is off leave (and are remembered), and
    /// those remembered return when their feature is on, if they fit. Does nothing unless something moves.
    func syncHomeWidgets() {
        var layout = homeLayout.restoring(homeHiddenByFeature.filter(isWidgetAllowed))
        var waiting = homeHiddenByFeature.filter { !isWidgetAllowed($0) }
        let (trimmed, taken) = layout.removingWidgets(where: { !isWidgetAllowed($0) })
        layout = trimmed
        for widget in taken where !waiting.contains(widget) { waiting.append(widget) }
        setHomeLayout(layout)
        if waiting != homeHiddenByFeature { homeHiddenByFeature = waiting }
    }

    /// Sets every feature to the preset's: one change for each that flips.
    func apply(_ preset: FeaturePreset) {
        for feature in Feature.allCases { setOn(feature, preset.features.contains(feature)) }
    }

    /// The preset the features are exactly at, or nil when they are the person's own.
    func matchingPreset() -> FeaturePreset? {
        FeaturePreset.allCases.first { preset in
            Feature.allCases.allSatisfy { isOn($0) == preset.features.contains($0) }
        }
    }

    /// Whether a module shows: it has a view, and its feature (if it has one) is on. Home is always shown.
    func isShown(_ module: IslandModule) -> Bool {
        module.isAvailable && (Feature.module(for: module).map(isOn) ?? true)
    }

    /// What a dragged file does: nothing while the Shelf is off.
    var effectiveDragTarget: DragTarget { isOn(.shelf) ? dragTarget : .nothing }

    /// The clipboard history's size as the model reads it: 0 while the Clipboard feature is off.
    var effectiveClipboardLimit: Int { isOn(.clipboard) ? clipboardLimit : 0 }

    // MARK: Menu bar

    func isInMenuBar(_ module: IslandModule) -> Bool { menuBarModules.contains(module) }

    /// Whether the module has its icon in the menu bar now: the person chose it, and its feature is on. A feature that is off keeps
    /// the choice, so the icon returns with it.
    func showsInMenuBar(_ module: IslandModule) -> Bool { isShown(module) && isInMenuBar(module) }

    /// Does nothing unless it changes something. SwiftUI calls this from a menu-bar scene's binding to keep the two
    /// in step, and a write that changed nothing would still count as a change and set it off again, forever.
    func setInMenuBar(_ module: IslandModule, _ inserted: Bool) {
        guard module.isAvailable, isInMenuBar(module) != inserted else { return }
        if inserted {
            menuBarModules.append(module)
        } else {
            menuBarModules.removeAll { $0 == module }
        }
    }

    // MARK: Tabs

    enum TabSide: String, CaseIterable, Identifiable {
        case left, right

        var id: Self { self }
        var capacity: Int { self == .left ? Theme.Metrics.maxTabs : Theme.Metrics.maxRightTabs }
    }

    /// Available modules only, none twice (the left side wins), in the order given, within each side's
    /// capacity. Nothing at all falls back to the defaults.
    static func normalized(left: [IslandModule], right: [IslandModule]) -> ([IslandModule], [IslandModule]) {
        var seen = Set<IslandModule>()
        func clean(_ modules: [IslandModule], capacity: Int) -> [IslandModule] {
            var kept: [IslandModule] = []
            for module in modules where module.isAvailable && kept.count < capacity && seen.insert(module).inserted {
                kept.append(module)
            }
            return kept
        }
        let newLeft = clean(left, capacity: Theme.Metrics.maxTabs)
        let newRight = clean(right, capacity: Theme.Metrics.maxRightTabs)
        return newLeft.isEmpty && newRight.isEmpty ? (IslandModule.defaultTabs, []) : (newLeft, newRight)
    }

    /// One list, for callers that don't care about sides: everything goes on the left.
    static func normalized(_ modules: [IslandModule]) -> [IslandModule] {
        normalized(left: modules, right: []).0
    }

    func isInTabs(_ module: IslandModule) -> Bool { side(of: module) != nil }

    func side(of module: IslandModule) -> TabSide? {
        if leftTabs.contains(module) { return .left }
        if rightTabs.contains(module) { return .right }
        return nil
    }

    func tabs(on side: TabSide) -> [IslandModule] { side == .left ? leftTabs : rightTabs }

    /// The tabs left of the notch that show: `leftTabs` without the modules whose feature is off. The stored lists never change
    /// because of a switch, so a module that is switched back on returns to its place. With nothing left, Home.
    var shownLeftTabs: [IslandModule] {
        let left = leftTabs.filter(isShown)
        return left.isEmpty && rightTabs.allSatisfy({ !isShown($0) }) ? [.home] : left
    }

    /// The tab right of the notch, if it shows.
    var shownRightTabs: [IslandModule] { rightTabs.filter(isShown) }

    /// Every tab that shows, left to right. Never empty.
    var shownTabs: [IslandModule] { shownLeftTabs + shownRightTabs }

    func shownTabs(on side: TabSide) -> [IslandModule] { side == .left ? shownLeftTabs : shownRightTabs }

    /// Modules that could be shown but aren't, in module order.
    var hiddenModules: [IslandModule] {
        IslandModule.allCases.filter { isShown($0) && !shownTabs.contains($0) }
    }

    func hasRoom(on side: TabSide) -> Bool { tabs(on: side).count < side.capacity }

    /// Whether a module could be turned on: either side has room.
    var canAddTab: Bool { hasRoom(on: .left) || hasRoom(on: .right) }

    /// Turns a tab on or off. On goes to the left, or the right if the left is full. The last tab can't be
    /// turned off.
    func setEnabled(_ module: IslandModule, _ enabled: Bool) {
        guard module.isAvailable else { return }
        if enabled {
            guard !isInTabs(module) else { return }
            if hasRoom(on: .left) {
                leftTabs.append(module)
            } else if hasRoom(on: .right) {
                rightTabs.append(module)
            }
        } else {
            guard isInTabs(module), shownTabs.count > 1 else { return }
            leftTabs.removeAll { $0 == module }
            rightTabs.removeAll { $0 == module }
        }
    }

    func toggleTab(_ module: IslandModule) {
        setEnabled(module, !isInTabs(module))
    }

    /// Puts a module on a side, before `other` (or last). Works from either side or from hidden. Refuses
    /// (and returns `false`) if the side is full and the module isn't already on it.
    @discardableResult
    func move(_ module: IslandModule, to side: TabSide, before other: IslandModule? = nil) -> Bool {
        guard module.isAvailable, module != other else { return false }
        let current = self.side(of: module)
        if current != side, !hasRoom(on: side) { return false }

        var left = leftTabs.filter { $0 != module }
        var right = rightTabs.filter { $0 != module }
        func insert(into list: inout [IslandModule]) {
            let index = other.flatMap { list.firstIndex(of: $0) } ?? list.count
            list.insert(module, at: index)
        }
        if side == .left { insert(into: &left) } else { insert(into: &right) }
        leftTabs = left
        rightTabs = right
        return true
    }

    /// Swaps two tabs: each takes the other's place, on either side of the notch. If `module` is in Not Shown, it takes the
    /// place of `target`, and `target` goes to Not Shown. Only a tab that is shown can be replaced. Returns false when
    /// nothing could change.
    @discardableResult
    func swapTab(_ module: IslandModule, with target: IslandModule) -> Bool {
        guard module.isAvailable, target.isAvailable, module != target, let targetSide = side(of: target) else {
            return false
        }
        var lists: [TabSide: [IslandModule]] = [.left: leftTabs, .right: rightTabs]
        if let from = side(of: module) {
            // Both are shown: each takes the other's place.
            guard let a = lists[from]?.firstIndex(of: module), let b = lists[targetSide]?.firstIndex(of: target) else {
                return false
            }
            lists[from]?[a] = target
            lists[targetSide]?[b] = module
        } else {
            guard let b = lists[targetSide]?.firstIndex(of: target) else { return false }
            lists[targetSide]?[b] = module
        }
        leftTabs = lists[.left] ?? leftTabs
        rightTabs = lists[.right] ?? rightTabs
        return true
    }

    /// Puts `module` at the place of the tab `target`, for the list in Settings (which can also make room).
    /// - On its own side, it takes the target's place and the ones between shift over.
    /// - On the other side (or from Not Shown), it goes in before the target if there is room. If the side is full, the two
    ///   **swap**: the dragged tab takes the target's place, and the target takes the dragged tab's old place (or goes to Not
    ///   Shown if the dragged one came from there).
    /// Returns false when nothing could change.
    @discardableResult
    func placeTab(_ module: IslandModule, before target: IslandModule) -> Bool {
        guard module.isAvailable, target.isAvailable, module != target, let targetSide = side(of: target) else {
            return false
        }
        var left = leftTabs
        var right = rightTabs
        func read(_ side: TabSide) -> [IslandModule] { side == .left ? left : right }
        func write(_ list: [IslandModule], _ side: TabSide) { if side == .left { left = list } else { right = list } }

        let from = side(of: module)
        var list = read(targetSide)
        if from == targetSide {
            let slot = list.firstIndex(of: target) ?? list.count
            list.removeAll { $0 == module }
            list.insert(module, at: min(slot, list.count))
            write(list, targetSide)
        } else if list.count < targetSide.capacity {
            if let from { write(read(from).filter { $0 != module }, from) }
            list.insert(module, at: list.firstIndex(of: target) ?? list.count)
            write(list, targetSide)
        } else {
            guard let slot = list.firstIndex(of: target) else { return false }
            list[slot] = module
            write(list, targetSide)
            if let from {
                var other = read(from)
                if let index = other.firstIndex(of: module) { other[index] = target }
                write(other, from)
            }
        }
        leftTabs = left
        rightTabs = right
        return true
    }

    /// Moving `module` to a side: last on it, or in place of its last tab when it is full.
    @discardableResult
    func moveTab(_ module: IslandModule, toSide side: TabSide) -> Bool {
        guard module.isAvailable else { return false }
        if self.side(of: module) == side { return move(module, to: side) }
        if hasRoom(on: side) { return move(module, to: side) }
        guard let last = tabs(on: side).last else { return false }
        return placeTab(module, before: last)
    }

    /// Turns a tab off or on and says whether it now is what was asked. For drop handlers.
    @discardableResult
    func setEnabledReturning(_ module: IslandModule, _ enabled: Bool) -> Bool {
        setEnabled(module, enabled)
        return isInTabs(module) == enabled
    }

    /// Up or down one place within its side.
    func nudge(_ module: IslandModule, by step: Int) {
        guard let side = side(of: module) else { return }
        var list = tabs(on: side)
        guard let index = list.firstIndex(of: module), list.indices.contains(index + step) else { return }
        list.swapAt(index, index + step)
        if side == .left { leftTabs = list } else { rightTabs = list }
    }

    // MARK: Pinned tools

    /// The row is always full: what the person pinned, then the remaining tools in their usual order,
    /// up to the row length (or every tool, if there are fewer).
    var visiblePinned: [ToolID] {
        Self.filled(
            Array(pinnedTools.filter(isKnown).prefix(pinLimit.rawValue)), to: pinLimit.rawValue, from: allTools)
    }

    // MARK: Shortcut tools

    /// Every tool: the built-in ones, then the person's own.
    var allTools: [ToolID] { ToolID.allCases + shortcutTools.map(\.toolID) }

    /// Whether `tool` exists: a built-in, or a Shortcut tool that is still there.
    func isKnown(_ tool: ToolID) -> Bool {
        tool.shortcutID.map { id in shortcutTools.contains { $0.id == id } } ?? true
    }

    func shortcutTool(for tool: ToolID) -> ShortcutTool? {
        tool.shortcutID.flatMap { id in shortcutTools.first { $0.id == id } }
    }

    func shortcutTool(id: UUID) -> ShortcutTool? { shortcutTools.first { $0.id == id } }

    var canAddShortcutTool: Bool { shortcutTools.count < Self.maxShortcutTools }

    /// Adds a Shortcut tool, or replaces the one with the same id. Refuses (false) one that isn't valid, or a new one when the
    /// Tools tab is full. Does nothing unless it changes something.
    @discardableResult
    func saveShortcutTool(_ tool: ShortcutTool) -> Bool {
        let tool = tool.cleaned
        guard tool.isValid else { return false }
        if let index = shortcutTools.firstIndex(where: { $0.id == tool.id }) {
            guard shortcutTools[index] != tool else { return true }
            shortcutTools[index] = tool
            return true
        }
        guard canAddShortcutTool else { return false }
        shortcutTools.append(tool)
        return true
    }

    /// Takes a Shortcut tool away, and off the row. The Shortcut itself is not touched.
    func removeShortcutTool(_ id: UUID) {
        guard shortcutTools.contains(where: { $0.id == id }) else { return }
        shortcutTools.removeAll { $0.id == id }
        let tool = ToolID(shortcut: id)
        if pinnedTools.contains(tool) { pinnedTools.removeAll { $0 == tool } }
    }

    /// For restoring: the valid ones, up to the room there is.
    func replaceShortcutTools(_ tools: [ShortcutTool]) {
        var kept: [ShortcutTool] = []
        for tool in tools.map(\.cleaned) where tool.isValid && kept.count < Self.maxShortcutTools {
            if !kept.contains(where: { $0.id == tool.id }) { kept.append(tool) }
        }
        guard kept != shortcutTools else { return }
        shortcutTools = kept
        pinnedTools.removeAll { !isKnown($0) }
    }

    /// Puts a pinned tool before another in the row, or last when `other` is nil. The row is what the Tools tab and
    /// Home's quick tools show, so this is how their order is chosen. Does nothing unless the order changes.
    func movePinned(_ tool: ToolID, before other: ToolID?) {
        var row = visiblePinned
        guard let from = row.firstIndex(of: tool), tool != other else { return }
        row.remove(at: from)
        if let other, let to = row.firstIndex(of: other) { row.insert(tool, at: to) } else { row.append(tool) }
        guard row != visiblePinned else { return }
        pinnedTools = row
    }

    func isPinned(_ tool: ToolID) -> Bool { visiblePinned.contains(tool) }

    /// Whether every tool already fits in the row, so pinning changes nothing.
    var rowShowsEveryTool: Bool { pinLimit.rawValue >= allTools.count }

    /// Pinning into a full row pushes out the tool that has been pinned longest. Unpinning leaves a gap
    /// that another tool fills, so the row never gets shorter.
    func togglePin(_ tool: ToolID) {
        var row = visiblePinned
        if let index = row.firstIndex(of: tool) {
            row.remove(at: index)
            row = Self.filled(row, to: pinLimit.rawValue, avoiding: tool, from: allTools)
        } else {
            if row.count >= pinLimit.rawValue { row.removeFirst() }
            row.append(tool)
        }
        pinnedTools = row
    }

    /// `row` topped up from `pool` to `count` tools. `avoiding` is used only if nothing else is left.
    static func filled(
        _ row: [ToolID], to count: Int, avoiding: ToolID? = nil, from pool: [ToolID] = ToolID.allCases
    ) -> [ToolID] {
        var row = row
        for tool in pool where row.count < count && !row.contains(tool) && tool != avoiding {
            row.append(tool)
        }
        if row.count < count, let avoiding, !row.contains(avoiding) { row.append(avoiding) }
        return row
    }
}
