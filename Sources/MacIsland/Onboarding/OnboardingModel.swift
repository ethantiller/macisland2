import Foundation
import Observation

/// How the guide ended. Every way is recorded as seen.
enum GuideEnding {
    case done, openSettings, closed, skipped
}

/// Walks the first-run guide: where it is, what the stage shows, which practice checks are met, and what each way out does.
@MainActor
@Observable
final class OnboardingModel {
    /// TEMPORARY (onboarding Skip): remove before release, with everything it guards; see docs/plans/onboarding-plan.md.
    /// Skip exists so the permission prompts can be tested without clicking through every step.
    static let showsSkip = true

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
    @ObservationIgnored private let startDeferredMonitors: () -> Void
    @ObservationIgnored private let openSettingsWindow: () -> Void
    @ObservationIgnored private let onEnd: (GuideEnding) -> Void
    @ObservationIgnored private var lastIsland: PracticeGoal.Island
    @ObservationIgnored private var ended = false

    init(
        state: OnboardingState, settings: AppSettings, geometry: @escaping () -> ScreenGeometry,
        preview: IslandPreviewModel, access: AccessModel, island: PracticeGoal.Island, replay: Bool,
        startDeferredMonitors: @escaping () -> Void, openSettings: @escaping () -> Void,
        onEnd: @escaping (GuideEnding) -> Void
    ) {
        self.state = state
        self.settings = settings
        self.geometry = geometry
        self.preview = preview
        self.access = access
        self.replay = replay
        self.startDeferredMonitors = startDeferredMonitors
        openSettingsWindow = openSettings
        self.onEnd = onEnd
        lastIsland = island
        flow = OnboardingFlow.make(seen: state.guideSeen, replay: replay, allAccessAllowed: access.allAllowed)
        showStage(animated: false)
    }

    /// The person's own setup, which the copy follows.
    var setup: GuideSetup {
        GuideSetup(
            openShortcut: settings.shortcut(.open), hasNotch: geometry().hasNotch, tabs: settings.tabs,
            hiddenModules: settings.hiddenModules, dragTarget: settings.dragTarget,
            addsScreenshots: settings.addsScreenshots)
    }

    var step: GuideStep { flow.current }
    var title: String { GuideCopy.title(step.id) }
    var copy: String { GuideCopy.body(step.id, setup: setup) }
    var practice: PracticeGoal? { GuideCopy.practice(for: step, setup: setup) }
    var isPracticeMet: Bool { practiceMet.contains(step.id) }
    var primaryTitle: String { GuideCopy.primaryTitle(step.id, isLast: flow.isLast) }

    // MARK: Moving

    func next(animated: Bool = true) {
        flow.next()
        showStage(animated: animated)
    }

    func back(animated: Bool = true) {
        flow.back()
        showStage(animated: animated)
    }

    func choose(_ module: IslandModule) {
        chosenModule = module
        showStage()
    }

    /// Continue, or Done on the last step.
    func advance() {
        if flow.isLast { finish() } else { next() }
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
    }

    // MARK: Open at Login

    /// Open at Login as the system has it. Read again when the last step appears, since System Settings can change it.
    var launchAtLogin: Bool { settings.launchAtLogin }

    func toggleLaunchAtLogin() { settings.setLaunchAtLogin(!settings.launchAtLogin) }

    /// Reads the system's setting again.
    func refreshLaunchAtLogin() { settings.refresh() }

    // MARK: Practice

    /// The live island changed. Marks the current step's goal met when this change is what it waits for.
    func observe(_ island: PracticeGoal.Island) {
        defer { lastIsland = island }
        guard let goal = practice, !practiceMet.contains(step.id), goal.isMet(from: lastIsland, to: island) else {
            return
        }
        practiceMet.insert(step.id)
    }

    // MARK: Ending

    func finish() { end(.done) }

    func close() { end(.closed) }

    func openSettings() {
        guard !ended else { return }
        if state.needsTour { state.tourRequested = true }
        end(.openSettings)
        openSettingsWindow()
    }

    /// TEMPORARY (onboarding Skip): ends the guide at once, then asks every permission still never asked, one at a time.
    /// The window closes first so the system prompts don't fight it for the screen.
    func skip() async {
        guard !ended else { return }
        end(.skipped)
        await access.requestAllPending()
        startDeferredMonitors()
    }

    /// Records the guide as seen and closes it. Whatever the way out, what was held back on a fresh install starts now.
    private func end(_ ending: GuideEnding) {
        guard !ended else { return }
        ended = true
        state.finishGuide()
        onEnd(ending)
        if ending != .skipped { startDeferredMonitors() }
    }

    /// Stops what the stage started.
    func stop() { preview.stop() }
}
