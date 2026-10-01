import Foundation

/// The guide's steps in order. After the tour of the island comes one step for each permission, each required.
enum GuideStepID: String, CaseIterable {
    case welcome, peek, open, tabs, close, modules, drop, menuBar
    case calendars, reminders, bluetooth, downloads, camera, microphone, screenRecording, accessibility, focus, automation
    case finish

    /// The permission a step is about, or nil for the rest.
    var accessKind: AccessKind? {
        switch self {
        case .calendars: .calendars
        case .reminders: .reminders
        case .bluetooth: .bluetooth
        case .downloads: .downloads
        case .camera: .camera
        case .microphone: .microphone
        case .screenRecording: .screenRecording
        case .accessibility: .accessibility
        case .focus: .focus
        case .automation: .automation
        default: nil
        }
    }

    init(_ kind: AccessKind) {
        switch kind {
        case .calendars: self = .calendars
        case .reminders: self = .reminders
        case .bluetooth: self = .bluetooth
        case .downloads: self = .downloads
        case .camera: self = .camera
        case .microphone: self = .microphone
        case .screenRecording: self = .screenRecording
        case .accessibility: self = .accessibility
        case .focus: self = .focus
        case .automation: self = .automation
        }
    }
}

/// What a practice line waits for on the stage island, the one in the guide's window.
enum PracticeGoal: Equatable {
    case peek, open, changeTab, close, dropFile

    /// What the island was and is now. Pure, so a goal is tested without a panel.
    struct Island: Equatable {
        var state: IslandViewModel.State
        var tab: IslandModule
        var isFileDragActive: Bool

        init(state: IslandViewModel.State, tab: IslandModule, isFileDragActive: Bool) {
            self.state = state
            self.tab = tab
            self.isFileDragActive = isFileDragActive
        }

        /// The island as it is right now.
        @MainActor
        init(_ viewModel: IslandViewModel) {
            self.init(state: viewModel.state, tab: viewModel.selectedTab, isFileDragActive: viewModel.isFileDragActive)
        }
    }

    func isMet(from old: Island, to new: Island) -> Bool {
        switch self {
        // With Peek on Hover off, a click still counts.
        case .peek: new.state == .peek || new.state == .expanded
        case .open: new.state == .expanded
        case .changeTab: new.state == .expanded && old.state == .expanded && new.tab != old.tab
        case .close: old.state != .compact && new.state == .compact
        case .dropFile: new.isFileDragActive && !old.isFileDragActive
        }
    }
}

struct GuideStep: Equatable {
    let id: GuideStepID
    /// The guide version that added it. A re-run for someone who saw version n shows the steps with a newer `since`.
    let since: Int
    let practice: PracticeGoal?
    /// What the stage starts as. A practice step starts as the island is before what it teaches, never as it is after, so the person
    /// does it. Nil for `menuBar`, which slides the band to the menu bar instead.
    let stage: PreviewContext?

    /// Whether the stage answers to the pointer, a click, swipes, a dragged file, and the keys. The menu bar and the banner are
    /// pictures.
    var stageIsInteractive: Bool { id != .menuBar && id.accessKind == nil }

    static let all: [GuideStep] = [
        GuideStep(id: .welcome, since: 1, practice: nil, stage: PreviewContext(presentation: .compact)),
        GuideStep(id: .peek, since: 1, practice: .peek, stage: PreviewContext(presentation: .compact)),
        GuideStep(id: .open, since: 1, practice: .open, stage: PreviewContext(presentation: .compact)),
        // Open, on Home: changing the tab and closing are done to an island that is already open.
        GuideStep(
            id: .tabs, since: 1, practice: .changeTab, stage: PreviewContext(presentation: .expanded, tab: .home)),
        GuideStep(
            id: .close, since: 1, practice: .close, stage: PreviewContext(presentation: .expanded, tab: .home)),
        GuideStep(
            id: .modules, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .home)),
        GuideStep(id: .drop, since: 1, practice: .dropFile, stage: PreviewContext(presentation: .compact)),
        GuideStep(id: .menuBar, since: 1, practice: nil, stage: nil),
        // One step for each permission, each showing what it gives. Every one is required: a step stays until it is allowed.
        GuideStep(id: .calendars, since: 1, practice: nil, stage: PreviewContext(presentation: .banner, event: .meeting)),
        GuideStep(
            id: .reminders, since: 1, practice: nil, stage: PreviewContext(presentation: .banner, event: .reminderDue)),
        GuideStep(
            id: .bluetooth, since: 1, practice: nil, stage: PreviewContext(presentation: .banner, event: .headphones)),
        GuideStep(
            id: .downloads, since: 1, practice: nil, stage: PreviewContext(presentation: .banner, event: .download)),
        GuideStep(
            id: .camera, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .tools)),
        GuideStep(
            id: .microphone, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .notes)),
        GuideStep(
            id: .screenRecording, since: 1, practice: nil,
            stage: PreviewContext(presentation: .expanded, tab: .tools)),
        GuideStep(
            id: .accessibility, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .tools)),
        GuideStep(id: .focus, since: 1, practice: nil, stage: PreviewContext(presentation: .compact)),
        GuideStep(
            id: .automation, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .media)),
        GuideStep(
            id: .finish, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .home)),
    ]
}

/// The steps a person walks through, and where they are.
struct OnboardingFlow: Equatable {
    private(set) var steps: [GuideStep]
    private(set) var index = 0

    /// Every step for a fresh install or a replay; for a re-run, the steps newer than `seen`, then `finish`. A permission's step is
    /// left out only when it is `allowed`, so there is nothing to ask. With `permissionsOnly` (a permission was taken away after the
    /// guide was done), the steps are the permissions that aren't allowed, then `finish`.
    static func make(
        seen: Int, replay: Bool, allowed: Set<AccessKind>, permissionsOnly: Bool = false
    ) -> OnboardingFlow {
        var steps =
            permissionsOnly
            ? GuideStep.all.filter { $0.id.accessKind != nil || $0.id == .finish }
            : GuideStep.all.filter { replay || seen == 0 || $0.since > seen || $0.id == .finish }
        steps.removeAll { step in step.id.accessKind.map(allowed.contains) ?? false }
        return OnboardingFlow(steps: steps)
    }

    var current: GuideStep { steps[index] }
    var count: Int { steps.count }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }

    mutating func next() { index = min(index + 1, steps.count - 1) }
    mutating func back() { index = max(index - 1, 0) }

    /// Starts at a step the guide stopped at. A step that was left out since (its permission is allowed now) starts at the next one
    /// after it, in `GuideStep.all` order, that is still here.
    mutating func start(at id: GuideStepID) {
        let order = GuideStep.all.map(\.id)
        guard let position = order.firstIndex(of: id) else { return }
        index = steps.firstIndex { order.firstIndex(of: $0.id).map { $0 >= position } ?? false } ?? steps.count - 1
    }

    /// Moves to a step, putting it back in its place first when it was left out (a permission allowed when the guide began, and
    /// taken away since).
    mutating func go(to id: GuideStepID) {
        if !steps.contains(where: { $0.id == id }), let step = GuideStep.all.first(where: { $0.id == id }) {
            let order = GuideStep.all.map(\.id)
            let position = order.firstIndex(of: id) ?? 0
            let at = steps.firstIndex { order.firstIndex(of: $0.id).map { $0 > position } ?? false } ?? steps.count
            steps.insert(step, at: at)
        }
        if let target = steps.firstIndex(where: { $0.id == id }) { index = target }
    }
}

/// What the person's own setup changes in the copy: their shortcut, their tabs, what a dragged file does, and whether the Mac
/// has a notch.
struct GuideSetup: Equatable {
    var openShortcut: KeyCombo?
    var shelfShortcut: KeyCombo? = nil
    var hasNotch: Bool
    var tabs: [IslandModule]
    var hiddenModules: [IslandModule]
    var dragTarget: DragTarget
    var addsScreenshots: Bool

    var notch: String { hasNotch ? "the notch" : "the top center of the screen" }
}

/// The guide's words. Titles are Title Case (they are labels) and copy is sentence case. Pure functions of the step and the
/// person's setup, so each sentence is tested.
enum GuideCopy {
    static func title(_ id: GuideStepID) -> String {
        switch id {
        case .welcome: "Welcome to MacIsland"
        case .peek: "Rest the Pointer to Peek"
        case .open: "Open It"
        case .tabs: "Change Tabs"
        case .close: "Fold It Away"
        case .modules: "Seven Modules"
        case .drop: "Drop Files on It"
        case .menuBar: "Keep a Module Close"
        case .calendars: "See Your Next Meeting"
        case .reminders: "See What\u{2019}s Due"
        case .bluetooth: "Know When Headphones Connect"
        case .downloads: "Watch Your Downloads"
        case .camera: "Check Yourself in Mirror"
        case .microphone: "Record Voice Notes"
        case .screenRecording: "Record Your Screen"
        case .accessibility: "Clean Your Keyboard"
        case .focus: "Stay Quiet in Focus"
        case .automation: "Control Music and Spotify"
        case .finish: "Make It Yours"
        }
    }

    static func body(_ id: GuideStepID, setup: GuideSetup) -> String {
        switch id {
        case .welcome:
            return "MacIsland turns the notch into a live island. It grows to show what\u{2019}s playing, what\u{2019}s counting down, and what\u{2019}s arriving, then folds back in."
        case .peek:
            return "Rest the pointer on \(setup.notch): the island swells, then shows what\u{2019}s live at full size. With nothing live, it shows your day and your everyday tools."
        case .open:
            var text = "Click the island or swipe down on it with two fingers."
            if let combo = setup.openShortcut { text += " From anywhere, press \(combo.display)." }
            return text
        case .tabs:
            var text = "Swipe sideways on it with two fingers."
            if let combo = setup.openShortcut {
                text += " When you opened it with \(combo.display), \u{2190} and \u{2192} switch tabs too."
            }
            return text
        case .close:
            let typing = "you\u{2019}re typing in it, it stays until you press Esc or click outside."
            if setup.openShortcut == nil {
                return "Move the pointer away and it folds back in, or swipe up on it. When \(typing)"
            }
            return "Move the pointer away and it folds back in, or swipe up on it. When you opened it from the keyboard, or \(typing)"
        case .modules:
            return modulesBody(setup)
        case .drop:
            return dropBody(setup)
        case .menuBar:
            return "Right-click a tab and choose Show in Menu Bar to give that module its own icon. Drag its window\u{2019}s header away to pop it out, and pin it there with Keep on Desktop."
        case .calendars:
            return "We need Calendars to show your next meeting in Up Next and a banner before it starts. Without it, your meetings stay out of the island."
        case .reminders:
            return "We need Reminders to show what\u{2019}s due in its tab and a banner when something is. Without it, the Reminders tab stays empty."
        case .bluetooth:
            return "We need Bluetooth to show you a notification when your AirPods connect, with their battery. Without it, there are no headphone banners and no device switcher."
        case .downloads:
            return "We need your Downloads folder to show progress while a file downloads and to tell you when it lands. Without it, downloads go unseen."
        case .camera:
            return "We need the camera for Mirror, a quick look at yourself before a call. Without it, Mirror stays off. Nothing is recorded or kept."
        case .microphone:
            return "We need the microphone and speech recognition for Voice Notes, which turn what you say into text on this Mac. Without them, a voice note can\u{2019}t be recorded."
        case .screenRecording:
            return "We need Screen Recording for Record Screen, which saves a movie of a region or your whole display. Without it, recording can\u{2019}t start. macOS asks you to reopen MacIsland afterward."
        case .accessibility:
            return "We need Accessibility for Clean Keys, which holds the keyboard still for 30 seconds while you wipe it. Without it, Clean Keys can\u{2019}t start."
        case .focus:
            return "We need Focus access so Quiet in Focus can hold banners back while a Focus is on. Without it, that setting does nothing."
        case .automation:
            return "We need permission to control Music and Spotify, so play, pause, and Favorite reach the right app. If neither is open, Music opens in the background so macOS can ask."
        case .finish:
            return "Choose your tabs, arrange Home, and pick what may interrupt you in Settings. The gear beside the tabs opens it."
        }
    }

    /// "Your tabs are Home, Media, and Tools. Shelf and Notes open when you need them. Choose one to see it."
    static func modulesBody(_ setup: GuideSetup) -> String {
        var text = "Your tabs are \(setup.tabs.map(\.title).formatted(.list(type: .and))). "
        if !setup.hiddenModules.isEmpty {
            let names = setup.hiddenModules.map(\.title).formatted(.list(type: .and))
            text += setup.hiddenModules.count == 1 ? "\(names) opens when you need it. " : "\(names) open when you need them. "
        }
        return text + "Choose one to see it."
    }

    static func dropBody(_ setup: GuideSetup) -> String {
        let screenshots = setup.addsScreenshots ? " New screenshots land on the Shelf by themselves." : ""
        let keys = setup.shelfShortcut.map { " \($0.display) opens the Shelf from anywhere." } ?? ""
        switch setup.dragTarget {
        case .shelfAndAirDrop:
            return "Drag a file toward \(setup.notch). Drop it on the left half to keep it on the Shelf, or on the right to AirDrop it."
                + screenshots + keys
        case .shelfOnly:
            return "Drag a file toward \(setup.notch). Drop it on the island to keep it on the Shelf." + screenshots + keys
        case .airDropOnly:
            return "Drag a file toward \(setup.notch). Drop it on the island to AirDrop it." + screenshots + keys
        case .nothing:
            return "Dragging files to the island is off. Turn it on in Settings \u{2192} Shelf." + keys
        }
    }

    /// What a permission step says once the person has answered, or before they have if the system won't say.
    /// `offItem` names what is off when it is not the step's own permission: Microphone's step also needs Speech Recognition.
    static func outcome(_ kind: AccessKind, state: PrivacyAccess.State, offItem: String? = nil) -> String {
        switch state {
        case .notAsked:
            return "Not asked yet."
        case .allowed:
            return kind == .calendars || kind == .reminders
                ? "Allowed, and turned on in Settings." : "Allowed."
        case .denied:
            switch kind {
            case .microphone:
                let item = offItem ?? "Microphone"
                return "\(item) is off, and macOS won\u{2019}t ask again. Turn on MacIsland in System Settings \u{2192} Privacy & Security \u{2192} \(item)."
            case .screenRecording:
                return "Turn on MacIsland in System Settings \u{2192} Privacy & Security \u{2192} Screen Recording, then reopen MacIsland."
            case .accessibility:
                return "Turn on MacIsland in System Settings \u{2192} Privacy & Security \u{2192} Accessibility. It takes effect at once."
            default:
                return "It\u{2019}s off, and macOS won\u{2019}t ask again. Turn it on in System Settings."
            }
        }
    }

    /// The key caps under a step, if it has any. Nothing when the open shortcut is off.
    static func keyCaps(_ id: GuideStepID, setup: GuideSetup) -> [String] {
        switch id {
        // The arrows switch tabs only after the keyboard opened the island, so without a shortcut there is nothing to name.
        case .tabs: setup.openShortcut == nil ? [] : ["\u{2190}", "\u{2192}"]
        case .close: ["Esc"]
        default: []
        }
    }

    /// Whether the step shows the open shortcut as key caps.
    static func showsShortcutCaps(_ id: GuideStepID, setup: GuideSetup) -> Bool {
        id == .open && setup.openShortcut != nil
    }

    /// A step's practice goal, or nil when there is nothing to try: dragging a file does nothing while the target is off.
    static func practice(for step: GuideStep, setup: GuideSetup) -> PracticeGoal? {
        if step.practice == .dropFile, setup.dragTarget == .nothing { return nil }
        return step.practice
    }

    /// What a practice line asks for. The island to do it on is the one above, in the guide's window.
    static func prompt(_ goal: PracticeGoal, setup: GuideSetup) -> String {
        switch goal {
        case .peek:
            return "Try it: rest the pointer on the island above."
        case .open:
            if let combo = setup.openShortcut { return "Try it: click the island above, or press \(combo.display)." }
            return "Try it: click the island above."
        case .changeTab:
            return "Try it: swipe sideways on the island above, or press \u{2190} or \u{2192}."
        case .close:
            return "Try it: move the pointer off the island above, or press Esc."
        case .dropFile:
            return "Try it: drag any file over the island above."
        }
    }

    /// One line about a module, for the Seven Modules step; a module that isn't a tab adds its other way in.
    static func moduleLines(_ module: IslandModule, inTabs: Bool) -> [String] {
        let line: String =
            switch module {
            case .home: "Widgets for your day: what\u{2019}s next, music, tools, and timers. Right-click one to edit Home."
            case .media: "What\u{2019}s playing in any app, with lyrics, shuffle, repeat, and where the sound goes."
            case .clock: "A timer, a stopwatch, and Pomodoro. Drag or swipe the dial to set a timer."
            case .reminders: "Add a reminder, and check off what\u{2019}s due."
            case .tools: "Keep Awake, Ring Light, Mute Mic, Mirror, Record Screen, and more. Right-click one to pin it."
            case .shelf: "Files you drop and what you copied. Right-click a file to convert, zip, or share it."
            case .notes: "Notes, snippets, a Prompter, and voice notes turned into text on this Mac."
            case .agents: ""
            }
        var lines = [line]
        if !inTabs, let other = module.otherWayIn { lines.append(other) }
        return lines
    }

    /// The prominent button: "Get Started" on the welcome, "Done" on the last step, "Continue" between.
    static func primaryTitle(_ id: GuideStepID, isLast: Bool) -> String {
        if isLast { return "Done" }
        return id == .welcome ? "Get Started" : "Continue"
    }
}
