import Foundation
import Testing

@testable import MacIsland

/// The guide asks for one permission per step: a reason, **Grant Permission**, and then what the answer was. Every permission is
/// required, so a step stays until its permission is allowed.
@MainActor
struct PermissionStepTests {
    private struct Rig {
        let model: OnboardingModel
        let access: StubAccess
        let settings: AppSettings
        let ends: Ends
    }

    private final class Ends { var list: [GuideEnding] = [] }

    private func makeRig(access: StubAccess? = nil, replay: Bool = false) -> Rig {
        let access = access ?? StubAccess()
        let suite = "MacIslandPermissionSteps.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let state = OnboardingState(defaults: defaults, isExistingInstall: { false })
        let reference = TestSupport.makeViewModel()
        let preview = IslandPreviewModel(live: reference.features)
        let accessModel = AccessModel(provider: access, settings: reference.settings, onBluetoothAllowed: {})
        let ends = Ends()
        let model = OnboardingModel(
            state: state, settings: reference.settings, geometry: { reference.geometry }, preview: preview,
            access: accessModel, replay: replay, openSettings: {}, onEnd: { ends.list.append($0) })
        return Rig(model: model, access: access, settings: reference.settings, ends: ends)
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

    @Test func theFooterFollowsTheAnswer() {
        let rig = makeRig(access: StubAccess(states: [.camera: .denied, .microphone: .allowed]))
        defer { rig.model.stop() }
        walk(rig.model, to: .calendars)
        #expect(rig.model.isAskingPermission && !rig.model.isDeniedPermission, "not asked: Grant Permission")
        walk(rig.model, to: .camera)
        #expect(rig.model.isDeniedPermission && !rig.model.isAskingPermission, "off: Open System Settings and Check Again")
        // Allowed steps are left out of the guide, so the one that is allowed has no step to show Continue on.
        #expect(!rig.model.flow.steps.contains { $0.id == .microphone })
    }

    @Test func aPermissionStepDoesNotGoOnUntilItIsAllowed() async {
        let rig = makeRig(access: StubAccess(answers: [.calendars: false]))
        defer { rig.model.stop() }
        walk(rig.model, to: .calendars)
        rig.model.advance()
        #expect(rig.model.step.id == .calendars, "not asked yet")
        await rig.model.grant()
        #expect(rig.model.accessState == .denied)
        rig.model.advance()
        #expect(rig.model.step.id == .calendars, "off")
        // Turned on in System Settings, then Check Again.
        rig.access.states[.calendars] = .allowed
        rig.model.checkAgain()
        #expect(rig.model.accessState == .allowed)
        rig.model.advance()
        #expect(rig.model.step.id == .reminders)
    }

    @Test func aGrantReadsAsAllowedEvenWhenTheSystemStillSaysNotAsked() async {
        // EventKit can report "not determined" for a moment after a grant.
        let access = LaggingAccess()
        let reference = TestSupport.makeViewModel()
        let model = AccessModel(provider: access, settings: reference.settings, onBluetoothAllowed: {})
        await model.allow(.calendars)
        #expect(access.requests == [.calendars])
        #expect(model.state(of: .calendars) == .allowed)
        model.refresh()
        #expect(model.state(of: .calendars) == .allowed, "a later read doesn't undo it")
        // The system saying no does.
        access.reads[.calendars] = .denied
        model.refresh()
        #expect(model.state(of: .calendars) == .denied)
    }

    /// A provider whose reads lag behind what it granted.
    private final class LaggingAccess: AccessProviding {
        var reads: [AccessKind: PrivacyAccess.State] = [:]
        private(set) var requests: [AccessKind] = []
        func state(of kind: AccessKind) -> PrivacyAccess.State { reads[kind] ?? .notAsked }
        func request(_ kind: AccessKind) async -> Bool {
            requests.append(kind)
            return true
        }
    }

    @Test func doneIsBlockedUntilEveryPermissionIsAllowed() {
        let rig = makeRig(access: StubAccess(states: [.focus: .denied, .calendars: .notAsked]))
        defer { rig.model.stop() }
        walk(rig.model, to: .finish)
        #expect(!rig.model.canFinish)
        #expect(rig.model.stillNeeded.contains(.focus) && rig.model.stillNeeded.contains(.calendars))
        rig.model.advance()
        rig.model.finish()
        #expect(rig.ends.list.isEmpty && rig.model.step.id == .finish)
        rig.access.states = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, .allowed) })
        rig.model.access.refresh()
        #expect(rig.model.canFinish && rig.model.stillNeeded.isEmpty)
        rig.model.advance()
        #expect(rig.ends.list == [.done])
    }

    @Test func aNameInStillNeededGoesBackToItsStep() {
        let rig = makeRig(access: StubAccess(states: [.focus: .denied]))
        defer { rig.model.stop() }
        walk(rig.model, to: .finish)
        #expect(rig.model.stillNeeded.first == .calendars)
        rig.model.go(to: GuideStepID(.focus), animated: false)
        #expect(rig.model.step.id == .focus)
        rig.model.go(to: .calendars, animated: false)
        #expect(rig.model.step.id == .calendars)
        // Back works on every step but the first, so earlier steps can be redone.
        rig.model.back(animated: false)
        #expect(rig.model.step.id == .menuBar)
    }

    @Test func anAllowedPermissionIsLeftOutAndTheRestStay() {
        let rig = makeRig(access: StubAccess(states: [.calendars: .allowed, .focus: .denied, .automation: .denied]))
        defer { rig.model.stop() }
        let kinds = rig.model.flow.steps.compactMap(\.id.accessKind)
        #expect(!kinds.contains(.calendars))
        #expect(kinds.contains(.focus) && kinds.contains(.automation), "off is shown, so it can be turned on")
        #expect(kinds.count == 9)
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
            for state in [PrivacyAccess.State.notAsked, .allowed, .denied] {
                #expect(!GuideCopy.outcome(kind, state: state).isEmpty)
            }
        }
        #expect(GuideCopy.body(.bluetooth, setup: setup).contains("AirPods connect"))
        #expect(GuideCopy.outcome(.screenRecording, state: .denied).contains("reopen"))
        #expect(GuideCopy.outcome(.camera, state: .notAsked) == "Not asked yet.")
        // Microphone's step names whichever of Microphone and Speech Recognition is off.
        #expect(GuideCopy.outcome(.microphone, state: .denied, offItem: "Speech Recognition").contains("Speech Recognition"))
        #expect(GuideCopy.outcome(.microphone, state: .denied).contains("Microphone"))
        for kind in AccessKind.allCases {
            #expect(GuideCopy.outcome(kind, state: .denied).contains("System Settings"), "\(kind)")
        }
        #expect(GuideCopy.body(.automation, setup: setup).contains("Music opens in the background"))
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
        #expect(AccessAsked.contains(.downloads, defaults: defaults) && !AccessAsked.contains(.screenRecording, defaults: defaults))
        #expect(defaults.stringArray(forKey: AccessAsked.key) == ["downloads"])
    }

    @Test func downloadsIsNotAskedUntilAskedThenReadsByListingTheFolder() {
        let suite = "MacIslandDownloads.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var listings = 0
        func state(readable: Bool) -> PrivacyAccess.State? {
            PrivacyAccess.current(defaults: defaults, downloadsReadable: {
                listings += 1
                return readable
            }).first { $0.id == "downloads" }?.state
        }
        // Listing the folder is what makes macOS ask, so before it was asked nothing is listed.
        #expect(state(readable: true) == .notAsked && listings == 0)
        AccessAsked.mark(.downloads, defaults: defaults)
        #expect(state(readable: true) == .allowed)
        #expect(state(readable: false) == .denied)
        #expect(listings == 2)
    }

    // MARK: Automation

    private let music = "com.apple.Music"
    private let spotify = "com.spotify.client"

    @Test func automationIsAllowedWhenEitherAppIsAllowed() {
        #expect(AutomationAccess.state(statuses: [music: noErr], cache: [:]) == .allowed)
        #expect(AutomationAccess.state(statuses: [music: AutomationAccess.denied, spotify: noErr], cache: [:]) == .allowed)
    }

    @Test func automationIsOffWhenAnAppIsDeniedAndNoneAllowed() {
        #expect(AutomationAccess.state(statuses: [music: AutomationAccess.denied], cache: [:]) == .denied)
        #expect(AutomationAccess.state(statuses: [:], cache: [music: "denied"]) == .denied)
    }

    @Test func automationIsNotAskedWhenNothingIsKnown() {
        #expect(AutomationAccess.state(statuses: [:], cache: [:]) == .notAsked)
        #expect(AutomationAccess.state(statuses: [music: AutomationAccess.wouldAsk], cache: [:]) == .notAsked)
        // An app that isn't running says nothing, and the cache stands.
        #expect(AutomationAccess.state(statuses: [music: AutomationAccess.notRunning], cache: [:]) == .notAsked)
    }

    @Test func automationStaysAllowedAfterMusicQuits() {
        let cache = AutomationAccess.updatedCache(statuses: [music: noErr], cache: [:])
        #expect(cache == [music: "allowed"])
        #expect(AutomationAccess.state(statuses: [music: AutomationAccess.notRunning], cache: cache) == .allowed)
        #expect(AutomationAccess.updatedCache(statuses: [music: AutomationAccess.notRunning], cache: cache) == cache)
    }

    @Test func automationForgetsAnAnswerThatWasReset() {
        let cache = [music: "allowed", spotify: "denied"]
        let updated = AutomationAccess.updatedCache(statuses: [music: AutomationAccess.wouldAsk], cache: cache)
        #expect(updated == [spotify: "denied"])
        #expect(AutomationAccess.updatedCache(statuses: [music: AutomationAccess.denied], cache: cache)[music] == "denied")
    }

    @Test func automationsLastAnswerIsKeptInDefaults() {
        let suite = "MacIslandAutomation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(AutomationAccess.cachedState(defaults: defaults) == .notAsked)
        AutomationAccess.store([music: noErr], defaults: defaults)
        #expect(defaults.dictionary(forKey: "access.automation") as? [String: String] == [music: "allowed"])
        #expect(AutomationAccess.cachedState(defaults: defaults) == .allowed)
        #expect(PrivacyAccess.current(defaults: defaults).first { $0.id == "automation" }?.state == .allowed)
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
