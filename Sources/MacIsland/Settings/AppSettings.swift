import Carbon.HIToolbox
import Observation

/// The shortcut that opens the island from the keyboard.
enum HotkeyChoice: String, CaseIterable, Identifiable {
    case controlOptionSpace
    case controlOptionI
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .controlOptionI: "⌃⌥I"
        case .off: "Off"
        }
    }

    /// `nil` when the shortcut is off.
    var keyCombo: (keyCode: UInt32, modifiers: UInt32)? {
        let modifiers = UInt32(controlKey | optionKey)
        switch self {
        case .controlOptionSpace: return (UInt32(kVK_Space), modifiers)
        case .controlOptionI: return (UInt32(kVK_ANSI_I), modifiers)
        case .off: return nil
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
    @ObservationIgnored var onHotkeyChange: ((HotkeyChoice) -> Void)?
    /// Calendar or Reminders was turned on or off.
    @ObservationIgnored var onAgendaChange: (() -> Void)?
    /// Quiet in Focus was turned on or off.
    @ObservationIgnored var onQuietChange: (() -> Void)?
    /// The weather city was edited.
    @ObservationIgnored var onWeatherChange: (() -> Void)?
    /// Synced Lyrics was turned on or off.
    @ObservationIgnored var onLyricsChange: (() -> Void)?

    private(set) var launchAtLogin: Bool

    var hotkey: HotkeyChoice {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Key.hotkey)
            onHotkeyChange?(hotkey)
        }
    }

    /// Hold back banners and short alerts while a Focus is on.
    var quietDuringFocus: Bool {
        didSet {
            defaults.set(quietDuringFocus, forKey: Key.quiet)
            onQuietChange?()
        }
    }

    /// Off until turned on, so macOS only asks for access when the person wants it.
    var showsCalendar: Bool {
        didSet {
            defaults.set(showsCalendar, forKey: Key.calendar)
            onAgendaChange?()
        }
    }

    var showsReminders: Bool {
        didSet {
            defaults.set(showsReminders, forKey: Key.reminders)
            onAgendaChange?()
        }
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

    var pinLimit: PinLimit {
        didSet { defaults.set(pinLimit.rawValue, forKey: Key.pinLimit) }
    }

    /// Tools in row order. Only the first `pinLimit` show; the rest wait behind More.
    private(set) var pinnedTools: [ToolID] {
        didSet { defaults.set(pinnedTools.map(\.rawValue), forKey: Key.pinned) }
    }

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

    /// The engine the palette searches with when no keyword is typed.
    var defaultSearchEngineID: String {
        didSet { defaults.set(defaultSearchEngineID, forKey: Key.searchEngine) }
    }

    /// Engines the person added, after the built-in ones.
    private(set) var customEngines: [SearchEngine] {
        didSet { defaults.set(try? JSONEncoder().encode(customEngines), forKey: Key.customEngines) }
    }

    /// Every tab, left to right. Never empty.
    var tabs: [IslandModule] { leftTabs + rightTabs }

    private enum Key {
        static let tabs = "tabs"
        static let leftTabs = "tabsLeft"
        static let menuBar = "menuBarModules"
        static let searchEngine = "searchEngine"
        static let customEngines = "customSearchEngines"
        static let rightTabs = "tabsRight"
        static let hotkey = "hotkey"
        static let quiet = "quietDuringFocus"
        static let calendar = "showsCalendar"
        static let reminders = "showsReminders"
        static let pinLimit = "pinLimit"
        static let fullCharge = "fullChargeLevel"
        static let lyrics = "showsLyrics"
        static let weatherCity = "weatherCity"
        static let pinned = "pinnedTools"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        launchAtLogin = LaunchAtLogin.isEnabled
        hotkey = defaults.string(forKey: Key.hotkey).flatMap(HotkeyChoice.init) ?? .controlOptionSpace
        quietDuringFocus = defaults.bool(forKey: Key.quiet)
        showsCalendar = defaults.bool(forKey: Key.calendar)
        showsReminders = defaults.bool(forKey: Key.reminders)
        weatherCity = defaults.string(forKey: Key.weatherCity) ?? ""
        showsLyrics = defaults.object(forKey: Key.lyrics) as? Bool ?? true
        let storedFull = defaults.integer(forKey: Key.fullCharge)
        fullChargeLevel = Self.fullChargeRange.contains(storedFull) ? storedFull : 100
        pinLimit = PinLimit(rawValue: defaults.integer(forKey: Key.pinLimit)) ?? .six
        pinnedTools = defaults.stringArray(forKey: Key.pinned)?.compactMap(ToolID.init) ?? ToolID.defaultPins
        menuBarModules = (defaults.stringArray(forKey: Key.menuBar) ?? []).compactMap(IslandModule.init).filter(\.isAvailable)
        defaultSearchEngineID = defaults.string(forKey: Key.searchEngine) ?? SearchEngine.defaultID
        customEngines = defaults.data(forKey: Key.customEngines).flatMap { try? JSONDecoder().decode([SearchEngine].self, from: $0) } ?? []
        // The strip before it had two sides was one list; it becomes the left side. A strip nobody changed
        // follows the default to its new shape.
        func stored(_ key: String) -> [IslandModule]? { defaults.stringArray(forKey: key)?.compactMap(IslandModule.init) }
        let legacy = stored(Key.tabs)
        let left = stored(Key.leftTabs) ?? (legacy == IslandModule.previousDefaultTabs ? IslandModule.defaultTabs : legacy) ?? []
        (leftTabs, rightTabs) = Self.normalized(left: left, right: stored(Key.rightTabs) ?? [])
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.set(enabled)
    }

    /// The user may have changed Login Items in System Settings.
    func refresh() {
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    // MARK: Menu bar

    func isInMenuBar(_ module: IslandModule) -> Bool { menuBarModules.contains(module) }

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

    // MARK: Search engines

    /// Built-in engines, then the person's own.
    var searchEngines: [SearchEngine] { SearchEngine.builtIn + customEngines }

    var defaultSearchEngine: SearchEngine {
        searchEngines.first { $0.id == defaultSearchEngineID } ?? SearchEngine.builtIn[0]
    }

    /// Adds an engine. Refuses (returning `false`) a template without `%s`, a keyword or name that is empty or
    /// already taken, or an address that isn't http or https.
    @discardableResult
    func addCustomEngine(name: String, keyword: String, template: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        let keyword = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        let template = template.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !keyword.isEmpty, !keyword.contains(" "), SearchEngine.isValid(template: template),
              !searchEngines.contains(where: { $0.keyword.lowercased() == keyword })
        else { return false }
        customEngines.append(SearchEngine(id: UUID().uuidString, name: name, keyword: keyword, template: template))
        return true
    }

    func removeCustomEngine(_ id: String) {
        customEngines.removeAll { $0.id == id }
        if defaultSearchEngineID == id { defaultSearchEngineID = SearchEngine.defaultID }
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

    /// Modules that could be shown but aren't, in module order.
    var hiddenModules: [IslandModule] {
        IslandModule.allCases.filter { $0.isAvailable && !isInTabs($0) }
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
            guard isInTabs(module), tabs.count > 1 else { return }
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
        Self.filled(Array(pinnedTools.prefix(pinLimit.rawValue)), to: pinLimit.rawValue)
    }

    func isPinned(_ tool: ToolID) -> Bool { visiblePinned.contains(tool) }

    /// Whether every tool already fits in the row, so pinning changes nothing.
    var rowShowsEveryTool: Bool { pinLimit.rawValue >= ToolID.allCases.count }

    /// Pinning into a full row pushes out the tool that has been pinned longest. Unpinning leaves a gap
    /// that another tool fills, so the row never gets shorter.
    func togglePin(_ tool: ToolID) {
        var row = visiblePinned
        if let index = row.firstIndex(of: tool) {
            row.remove(at: index)
            row = Self.filled(row, to: pinLimit.rawValue, avoiding: tool)
        } else {
            if row.count >= pinLimit.rawValue { row.removeFirst() }
            row.append(tool)
        }
        pinnedTools = row
    }

    /// `row` topped up from `ToolID.allCases` to `count` tools. `avoiding` is used only if nothing else is left.
    static func filled(_ row: [ToolID], to count: Int, avoiding: ToolID? = nil) -> [ToolID] {
        var row = row
        for tool in ToolID.allCases where row.count < count && !row.contains(tool) && tool != avoiding {
            row.append(tool)
        }
        if row.count < count, let avoiding, !row.contains(avoiding) { row.append(avoiding) }
        return row
    }
}
