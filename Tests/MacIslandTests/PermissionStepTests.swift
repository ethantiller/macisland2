import Foundation
import Testing

@testable import MacIsland

/// The guide asks for one permission per step: a reason, **Grant Permission**, and **Not Now**. Nothing asks until Grant is pressed.
@MainActor
struct PermissionStepTests {
    private struct Rig {
        let model: OnboardingModel
        let access: StubAccess
        let settings: AppSettings
    }

    private func makeRig(access: StubAccess? = nil, replay: Bool = false) -> Rig {
        let access = access ?? StubAccess()
        let suite = "MacIslandPermissionSteps.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = OnboardingState(defaults: defaults, isExistingInstall: { false })
        let reference = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: reference.features)
        let accessModel = AccessModel(provider: access, settings: reference.settings, onBluetoothAllowed: {})
        let model = OnboardingModel(
            state: state, settings: reference.settings, geometry: { reference.geometry }, preview: preview,
            access: accessModel, replay: replay, startDeferredMonitors: {}, openSettings: {}, onEnd: { _ in })
        return Rig(model: model, access: access, settings: reference.settings)
    }

    private func walk(_ model: OnboardingModel, to id: GuideStepID) {
        for _ in 0..<40 where model.step.id != id { model.next(animated: false) }
    }

    @Test func reachingAStepAsksNothing() {
        let rig = makeRig()
        defer { rig.model.stop() }
        walk(rig.model, to: .calendars)
        #expect(rig.model.accessKind == .calendars && rig.model.isAskingPermission)
        #expect(rig.access.requests.isEmpty)
        // A step that isn't about a permission offers neither button.
        walk(rig.model, to: .finish)
        #expect(rig.model.accessKind == nil && !rig.model.isAskingPermission)
    }

    @Test func grantPermissionAsksOnlyThatOneAndStaysToShowTheAnswer() async {
        let rig = makeRig()
        defer { rig.model.stop() }
        walk(rig.model, to: .calendars)
        await rig.model.grant()
        #expect(rig.access.requests == [.calendars])
        #expect(rig.model.step.id == .calendars && rig.model.accessState == .allowed)
        #expect(!rig.model.isAskingPermission, "the footer goes back to Continue")
        #expect(rig.settings.showsCalendar, "a grant turns on what it serves")
        // Asking again does nothing: it isn't waiting any more.
        await rig.model.grant()
        #expect(rig.access.requests == [.calendars])
    }

    @Test func aDeniedAnswerIsShownAndNotAskedAgain() async {
        let rig = makeRig(access: StubAccess(answers: [.camera: false]))
        defer { rig.model.stop() }
        walk(rig.model, to: .camera)
        await rig.model.grant()
        #expect(rig.model.accessState == .denied && !rig.model.isAskingPermission)
        #expect(GuideCopy.outcome(.camera, state: .denied).contains("System Settings"))
        #expect(!rig.settings.showsCalendar)
        await rig.model.grant()
        #expect(rig.access.requests == [.camera])
    }

    @Test func notNowAsksNothingAndGoesOn() {
        let rig = makeRig()
        defer { rig.model.stop() }
        walk(rig.model, to: .calendars)
        rig.model.notNow()
        #expect(rig.model.step.id == .reminders)
        #expect(rig.access.requests.isEmpty)
        #expect(rig.model.access.state(of: .calendars) == .notAsked)
        // Not Now on a step that isn't a permission does nothing.
        walk(rig.model, to: .finish)
        rig.model.notNow()
        #expect(rig.model.step.id == .finish)
    }

    @Test func theGuideIsCompletableByPressingNotNowOnEveryPermission() {
        let rig = makeRig()
        defer { rig.model.stop() }
        var permissionSteps: [AccessKind] = []
        while !rig.model.flow.isLast {
            if let kind = rig.model.accessKind {
                permissionSteps.append(kind)
                rig.model.notNow()
            } else {
                rig.model.advance()
            }
        }
        #expect(rig.model.step.id == .finish)
        #expect(permissionSteps == AccessKind.allCases)
        #expect(rig.access.requests.isEmpty)
    }

    @Test func aPermissionAlreadySettledHasNoStep() {
        let rig = makeRig(access: StubAccess(states: [.calendars: .allowed, .downloads: .asked, .focus: .denied]))
        defer { rig.model.stop() }
        let kinds = rig.model.flow.steps.compactMap(\.id.accessKind)
        #expect(!kinds.contains(.calendars) && !kinds.contains(.downloads))
        #expect(kinds.contains(.focus), "an answer of no can still be turned on in System Settings, so it is shown")
        #expect(kinds.count == 8)
    }

    @Test func everyStepSaysWhatItNeedsAndWhatIsLostWithoutIt() {
        let setup = GuideSetup(
            openShortcut: nil, hasNotch: true, tabs: [], hiddenModules: [], dragTarget: .nothing, addsScreenshots: false)
        for kind in AccessKind.allCases {
            let id = GuideStepID(kind)
            let body = GuideCopy.body(id, setup: setup)
            #expect(body.hasPrefix("We need"), "\(kind)")
            #expect(body.count <= 240, "\(kind) is \(body.count) characters: the guide shows three lines")
            #expect(!GuideCopy.title(id).isEmpty)
            for state in [PrivacyAccess.State.notAsked, .allowed, .asked, .denied] {
                #expect(!GuideCopy.outcome(kind, state: state).isEmpty)
            }
        }
        #expect(GuideCopy.body(.bluetooth, setup: setup).contains("AirPods connect"))
        #expect(GuideCopy.outcome(.screenRecording, state: .denied).contains("reopen"))
    }

    @Test func aPermissionStepsStageIsAPictureSoItLeavesTheKeysToTheRealIsland() {
        for step in GuideStep.all where step.id.accessKind != nil {
            #expect(!step.stageIsInteractive && step.stage != nil, "\(step.id)")
        }
    }

    // MARK: What is remembered, and what the system says

    @Test func whatHasBeenAskedIsRemembered() {
        let suite = "MacIslandAsked.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(!AccessAsked.contains(.downloads, defaults: defaults))
        AccessAsked.mark(.downloads, defaults: defaults)
        AccessAsked.mark(.downloads, defaults: defaults)
        #expect(AccessAsked.contains(.downloads, defaults: defaults) && !AccessAsked.contains(.automation, defaults: defaults))
        #expect(defaults.stringArray(forKey: AccessAsked.key) == ["downloads"])
    }

    @Test func downloadsAndAutomationAreNotAskedUntilAskedThenAskedNeverAllowed() {
        let suite = "MacIslandAskedRows.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        func state(_ id: String) -> PrivacyAccess.State? {
            PrivacyAccess.current(defaults: defaults).first { $0.id == id }?.state
        }
        #expect(state("downloads") == .notAsked && state("automation") == .notAsked)
        AccessAsked.mark(.downloads, defaults: defaults)
        #expect(state("downloads") == .asked, "the system won't say what the answer was")
        #expect(state("automation") == .notAsked)
    }

    // MARK: Nothing touches a protected folder at launch

    @Test func theShelfDoesNotLookInProtectedFoldersUntilItIsShown() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(ShelfModel.isInProtectedFolder(home + "/Downloads/a.zip"))
        #expect(ShelfModel.isInProtectedFolder(home + "/Desktop/shot.png"))
        #expect(ShelfModel.isInProtectedFolder(home + "/Documents/x/y.pdf"))
        #expect(!ShelfModel.isInProtectedFolder(home + "/Movies/a.mov"))
        #expect(!ShelfModel.isInProtectedFolder("/tmp/a.txt"))

        let suite = "MacIslandShelfLaunch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let gone = home + "/Downloads/macisland-test-\(UUID().uuidString).txt"
        defaults.set([gone], forKey: "shelf.paths")
        let shelf = ShelfModel(defaults: defaults)
        #expect(shelf.items == [URL(fileURLWithPath: gone)], "taken on trust at launch: nothing was looked up")
        #expect(shelf.verify() == 1 && shelf.items.isEmpty, "checked once the Shelf is shown")
    }
}
