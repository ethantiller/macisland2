import Carbon.HIToolbox
import Foundation
import Observation

/// How the guide ended. Only Done and Open Settings end it, and both need every permission allowed.
enum GuideEnding {
    case done, openSettings
}

/// Walks the first-run guide: where it is, what the stage shows, which practice checks are met, and what each way out does.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var flow: OnboardingFlow
    /// Steps whose practice check has turned green. Kept when going back, so a finished check stays finished.
    private(set) var practiceMet: Set<GuideStepID> = []
    /// The module the Seven Modules step shows.
    private(set) var chosenModule: IslandModule = .home

    let preview: IslandPreviewModel
    let access: AccessModel
    let replay: Bool

    @ObservationIgnored private let state: OnboardingState
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let geometry: () -> ScreenGeometry
    @ObservationIgnored private let openSettingsWindow: () -> Void
    @ObservationIgnored private let onEnd: (GuideEnding) -> Void
    @ObservationIgnored private var lastIsland: PracticeGoal.Island
    @ObservationIgnored private var ended = false

    init(
        state: OnboardingState, settings: AppSettings, geometry: @escaping () -> ScreenGeometry,
        preview: IslandPreviewModel, access: AccessModel, replay: Bool, permissionsOnly: Bool = false,
        openSettings: @escaping () -> Void, onEnd: @escaping (GuideEnding) -> Void
    ) {
        self.state = state
        self.settings = settings
        self.geometry = geometry
        self.preview = preview
        self.access = access
        self.replay = replay
        openSettingsWindow = openSettings
        self.onEnd = onEnd
        lastIsland = PracticeGoal.Island(preview.viewModel)
        var flow = OnboardingFlow.make(
            seen: state.guideSeen, replay: replay, allowed: access.allowed, permissionsOnly: permissionsOnly)
        // A relaunch picks the guide up where it stopped. What was practised before that point stays practised.
        var practised: Set<GuideStepID> = []
        if !replay, let resume = state.resumeStep {
            flow.start(at: resume)
            practised = Set(flow.steps[..<flow.index].filter { $0.practice != nil }.map(\.id))
        }
        self.flow = flow
        practiceMet = practised
        showStage(animated: false)
    }

    /// The island in the guide's window, which the practice checks watch and the keys drive.
    var stageIsland: IslandViewModel { preview.viewModel }

    /// The person's own setup, which the copy follows.
    var setup: GuideSetup {
        GuideSetup(
            openShortcut: settings.shortcut(.open), shelfShortcut: settings.shortcut(.shelf), hasNotch: geometry().hasNotch, tabs: settings.shownTabs,
            hiddenModules: settings.hiddenModules, dragTarget: settings.dragTarget,
            addsScreenshots: settings.addsScreenshots)
    }

    /// The modules that are on, which the guide's chips and copy are about.
    var shownModules: [IslandModule] { IslandModule.allCases.filter(settings.isShown) }

    var step: GuideStep { flow.current }
    var title: String { GuideCopy.title(step.id) }
    var copy: String { GuideCopy.body(step.id, setup: setup) }
    var practice: PracticeGoal? { GuideCopy.practice(for: step, setup: setup) }
    var isPracticeMet: Bool { practiceMet.contains(step.id) }
    var primaryTitle: String { GuideCopy.primaryTitle(step.id, isLast: flow.isLast) }

    // MARK: Permissions

    /// The permission this step is about, if it is one.
    var accessKind: AccessKind? { step.id.accessKind }

    /// Where that permission stands now.
    var accessState: PrivacyAccess.State? { accessKind.map { access.state(of: $0) } }

    /// A permission step that is still waiting for an answer: it offers **Grant Permission** instead of Continue.
    var isAskingPermission: Bool { accessState == .notAsked }

    /// A permission step whose answer is no: it offers **Open System Settings** and **Check Again**, and no Continue.
    var isDeniedPermission: Bool { accessState == .denied }

    /// **Grant Permission**: the system prompt appears only now. The step stays, showing how it was answered.
    func grant() async {
        guard let kind = accessKind else { return }
        await access.allow(kind)
    }

    /// What is off on this step when it is not the step's own name (Speech Recognition, for Microphone), and where to turn it on.
    var offItem: PrivacyAccess.Item? { accessKind.flatMap { access.offItem(of: $0) } }

    /// **Check Again**: reads the permission again, after it was turned on in System Settings.
    func checkAgain() { access.refresh() }

    /// Whether the guide can end: every permission is allowed.
    var canFinish: Bool { access.allAllowed }

    /// The permissions still to allow, which the last step names.
    var stillNeeded: [AccessKind] { access.missing }

    // MARK: Moving

    func next(animated: Bool = true) {
        flow.next()
        moved(animated: animated)
    }

    func back(animated: Bool = true) {
        flow.back()
        moved(animated: animated)
    }

    /// Jumps to a step, from the last step's list of what is still needed.
    func go(to id: GuideStepID, animated: Bool = true) {
        flow.go(to: id)
        moved(animated: animated)
    }

    private func moved(animated: Bool) {
        if !replay { state.resumeStep = step.id }
        showStage(animated: animated)
    }

    func choose(_ module: IslandModule) {
        chosenModule = module
        showStage()
    }

    /// The stage island changed its tab on its own (a swipe, an arrow key). The Seven Modules step follows, so its chips and its line
    /// keep naming what is showing.
    func stageChangedTab(_ tab: IslandModule) {
        guard step.id == .modules, tab != chosenModule else { return }
        chosenModule = tab
    }

    /// Continue, or Done on the last step. A permission step goes on only once its permission is allowed, and Done only once all are.
    func advance() {
        if flow.isLast {
            finish()
        } else if accessKind == nil || accessState == .allowed {
            next()
        }
    }

    private func showStage(animated: Bool = true) {
        if step.id == .menuBar {
            // `showMenuBar(.clock)`, which keeps everything else about the preview as it was.
            var next = preview.context
            next.presentation = .menuBar
            next.menuBarTab = .clock
            preview.show(next, animated: animated)
        } else if step.id == .modules {
            preview.show(PreviewContext(presentation: .expanded, tab: chosenModule), animated: animated)
        } else if let stage = step.stage {
            preview.show(stage, animated: animated)
        }
        // Moving between steps is not doing what a step teaches: what the island changed to here is the new starting point.
        lastIsland = PracticeGoal.Island(stageIsland)
    }

    // MARK: Open at Login

    /// Open at Login as the system has it. Read again when the last step appears, since System Settings can change it.
    var launchAtLogin: Bool { settings.launchAtLogin }

    func toggleLaunchAtLogin() { settings.setLaunchAtLogin(!settings.launchAtLogin) }

    /// Reads the system's setting again.
    func refreshLaunchAtLogin() { settings.refresh() }

    // MARK: Practice

    /// The stage island changed. Marks the current step's goal met when this change is what it waits for.
    func observe(_ island: PracticeGoal.Island) {
        defer { lastIsland = island }
        guard let goal = practice, !practiceMet.contains(step.id), goal.isMet(from: lastIsland, to: island) else {
            return
        }
        practiceMet.insert(step.id)
    }

    // MARK: Keys

    /// Esc, ←, and → from the guide's window, for the stage island. Returns whether the key was taken.
    ///
    /// Esc is always taken: it closes the stage island when that is open and does nothing otherwise, and it never ends the guide,
    /// which only its own buttons do.
    func handleKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Escape:
            if step.stageIsInteractive, stageIsland.state != .compact { stageIsland.closePinned() }
            return true
        case kVK_LeftArrow, kVK_RightArrow:
            guard step.stageIsInteractive, stageIsland.state == .expanded else { return false }
            stageIsland.selectAdjacentTab(Int(keyCode) == kVK_LeftArrow ? -1 : 1)
            return true
        default:
            return false
        }
    }

    /// The open shortcut, while the guide is up: it opens or closes the stage island and pins it, as it does the real island. False
    /// when this step's stage is a picture, so the shortcut goes to the real island as usual.
    func toggleStageFromKeyboard() -> Bool {
        guard step.stageIsInteractive else { return false }
        stageIsland.toggleFromKeyboard()
        return true
    }

    // MARK: Ending

    func finish() {
        guard canFinish else { return }
        end(.done)
    }

    func openSettings() {
        guard !ended, canFinish else { return }
        if state.needsTour { state.tourRequested = true }
        end(.openSettings)
        openSettingsWindow()
    }

    /// Records the guide as seen and closes it. The app opens the island, and starts what waited for it, when it hears.
    private func end(_ ending: GuideEnding) {
        guard !ended else { return }
        ended = true
        state.resumeStep = nil
        state.finishGuide()
        onEnd(ending)
    }

    /// Stops what the stage started.
    func stop() { preview.stop() }
}
