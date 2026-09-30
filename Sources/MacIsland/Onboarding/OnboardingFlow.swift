import Foundation

enum GuideStepID: String, CaseIterable {
    case welcome, peek, open, tabs, close, modules, drop, menuBar, access, finish
}

/// What a practice line waits for on the real island.
enum PracticeGoal: Equatable {
    case peek, open, changeTab, close, dropFile

    /// What the island was and is now. Pure, so a goal is tested without a panel.
    struct Island: Equatable {
        var state: IslandViewModel.State
        var tab: IslandModule
        var isFileDragActive: Bool
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
    /// What the stage shows. Nil for `menuBar`, which slides the band to the menu bar instead.
    let stage: PreviewContext?

    static let all: [GuideStep] = [
        GuideStep(id: .welcome, since: 1, practice: nil, stage: PreviewContext(presentation: .compact)),
        GuideStep(id: .peek, since: 1, practice: .peek, stage: PreviewContext(presentation: .peek)),
        GuideStep(
            id: .open, since: 1, practice: .open, stage: PreviewContext(presentation: .expanded, tab: .home)),
        GuideStep(
            id: .tabs, since: 1, practice: .changeTab, stage: PreviewContext(presentation: .expanded, tab: .media)),
        GuideStep(id: .close, since: 1, practice: .close, stage: PreviewContext(presentation: .compact)),
        GuideStep(
            id: .modules, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .home)),
        GuideStep(
            id: .drop, since: 1, practice: .dropFile,
            stage: PreviewContext(presentation: .compact, tab: .shelf, fileDrag: true)),
        GuideStep(id: .menuBar, since: 1, practice: nil, stage: nil),
        GuideStep(
            id: .access, since: 1, practice: nil, stage: PreviewContext(presentation: .banner, event: .meeting)),
        GuideStep(
            id: .finish, since: 1, practice: nil, stage: PreviewContext(presentation: .expanded, tab: .home)),
    ]
}

/// The steps a person walks through, and where they are.
struct OnboardingFlow: Equatable {
    private(set) var steps: [GuideStep]
    private(set) var index = 0

    /// Every step for a fresh install or a replay; for a re-run, the steps newer than `seen`, then `finish`. `access` is left
    /// out when every permission it offers is already allowed.
    static func make(seen: Int, replay: Bool, allAccessAllowed: Bool) -> OnboardingFlow {
        var steps = GuideStep.all.filter { replay || seen == 0 || $0.since > seen || $0.id == .finish }
        if allAccessAllowed { steps.removeAll { $0.id == .access } }
        return OnboardingFlow(steps: steps)
    }

    var current: GuideStep { steps[index] }
    var count: Int { steps.count }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }

    mutating func next() { index = min(index + 1, steps.count - 1) }
    mutating func back() { index = max(index - 1, 0) }
}

/// What the person's own setup changes in the copy: their shortcut, their tabs, what a dragged file does, and whether the Mac
/// has a notch.
struct GuideSetup: Equatable {
    var openShortcut: KeyCombo?
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
        case .access: "Allow What You\u{2019}ll Use"
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
        case .access:
            return "Each is optional, and you can change it later in System Settings. Settings \u{2192} Privacy shows where each one stands."
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
        switch setup.dragTarget {
        case .shelfAndAirDrop:
            return "Drag a file toward \(setup.notch). Drop it on the left half to keep it on the Shelf, or on the right to AirDrop it."
                + screenshots
        case .shelfOnly:
            return "Drag a file toward \(setup.notch). Drop it on the island to keep it on the Shelf." + screenshots
        case .airDropOnly:
            return "Drag a file toward \(setup.notch). Drop it on the island to AirDrop it." + screenshots
        case .nothing:
            return "Dragging files to the island is off. Turn it on in Settings \u{2192} Shelf."
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

    static func prompt(_ goal: PracticeGoal, setup: GuideSetup) -> String {
        switch goal {
        case .peek: "Try it: rest the pointer on \(setup.notch)."
        case .open: "Try it: click \(setup.notch)."
        case .changeTab: "Try it: open the island, then swipe sideways."
        case .close: "Try it: open the island, then move the pointer away."
        case .dropFile: "Try it: drag any file toward \(setup.notch)."
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
