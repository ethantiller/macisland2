import Foundation
import Testing

@testable import MacIsland

/// Answers every access question from a table, and records what was asked, so no real permission is ever requested.
@MainActor
private final class OptionalStub: AccessProviding {
    var kinds: PrivacyAccess.State = .allowed
    var optional: [OptionalAccess: OptionalAccessState] = [:]
    private(set) var kindRequests: [AccessKind] = []
    private(set) var optionalRequests: [OptionalAccess] = []

    func state(of kind: AccessKind) -> PrivacyAccess.State { kinds }

    func request(_ kind: AccessKind) async -> Bool {
        kindRequests.append(kind)
        return true
    }

    func state(of access: OptionalAccess) -> OptionalAccessState { optional[access] ?? .notAsked }

    func request(_ access: OptionalAccess) async {
        optionalRequests.append(access)
        optional[access] = .asked
    }
}

@MainActor
struct OptionalAccessTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MacIslandOptionalAccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeModel(_ stub: OptionalStub) -> (AccessModel, AppSettings) {
        let settings = AppSettings(defaults: makeDefaults())
        return (AccessModel(provider: stub, settings: settings, onBluetoothAllowed: {}), settings)
    }

    @Test func anOptionalPermissionNeverClosesTheGate() {
        let stub = OptionalStub()
        stub.optional[.systemAudio] = .denied
        let (model, _) = makeModel(stub)
        #expect(model.allAllowed && model.missing.isEmpty)
        #expect(model.state(of: .systemAudio) == .denied)
        #expect(AccessKind.allCases.count == 10, "the guide still walks through the same ten")
    }

    @Test func turningOnAFeatureDoesNotAsk() {
        let stub = OptionalStub()
        let (model, settings) = makeModel(stub)
        settings.setOn(.mixer, true)
        #expect(stub.optionalRequests.isEmpty && stub.kindRequests.isEmpty)
        #expect(model.optionalAccessToAsk(for: .mixer) == [.systemAudio], "the pane offers Allow")
        #expect(model.optionalAccessToAsk(for: .music).isEmpty)
    }

    @Test func allowAsksOnlyThatOneOnce() async {
        let stub = OptionalStub()
        let (model, _) = makeModel(stub)
        await model.allow(.systemAudio)
        #expect(stub.optionalRequests == [.systemAudio] && stub.kindRequests.isEmpty)
        #expect(model.state(of: .systemAudio) == .asked && model.askingOptional == nil)
        await model.allow(.systemAudio)
        #expect(stub.optionalRequests == [.systemAudio], "asked once")
        #expect(model.optionalAccessToAsk(for: .mixer).isEmpty)
    }

    @Test func aPresetAsksNothing() {
        let stub = OptionalStub()
        let (model, settings) = makeModel(stub)
        settings.apply(.everything)
        #expect(settings.isOn(.mixer))
        #expect(stub.optionalRequests.isEmpty && stub.kindRequests.isEmpty)
        #expect(model.optionalAccessToAsk(for: .mixer) == [.systemAudio], "its row shows the line instead")
    }

    @Test func theStateIsWhatWasSeen() async {
        let defaults = makeDefaults()
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: defaults) == .notAsked)
        OptionalAccessRecord.record(.asked, for: .systemAudio, defaults: defaults)
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: defaults) == .asked)
        OptionalAccessRecord.record(.allowed, for: .systemAudio, defaults: defaults)
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: defaults) == .allowed)
        // Asking again doesn't undo what sound showed.
        OptionalAccessRecord.record(.asked, for: .systemAudio, defaults: defaults)
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: defaults) == .allowed)
        OptionalAccessRecord.record(.denied, for: .systemAudio, defaults: defaults)
        #expect(OptionalAccessRecord.state(of: .systemAudio, defaults: defaults) == .denied)

        // The real provider records that it asked, and runs the probe the Mixer sets.
        let fresh = makeDefaults()
        let live = LiveAccess(
            agenda: AgendaMonitor(), bluetooth: BluetoothAccess(), transfers: TransferMonitor(), defaults: fresh)
        var probes = 0
        live.systemAudioProbe = { probes += 1 }
        #expect(live.state(of: .systemAudio) == .notAsked)
        await live.request(.systemAudio)
        #expect(probes == 1 && live.state(of: .systemAudio) == .asked)
        #expect(OptionalAccessState.asked.words == "Can\u{2019}t Be Checked")
    }

    @Test func theEvidenceIsNotInstallEvidence() {
        #expect(!InstallEvidence.keys.contains(OptionalAccessRecord.key), "it records an answer, not use")
    }

    @Test func privacyListsWhatUsesIt() {
        let settings = AppSettings(defaults: makeDefaults())
        #expect(OptionalAccess.systemAudio.usage(settings: settings).hasPrefix("Nothing that is on uses it"))
        settings.setOn(.mixer, true)
        #expect(OptionalAccess.systemAudio.usage(settings: settings) == "Used by Mixer")
        #expect(OptionalAccess.systemAudio.feature.optionalAccess == [.systemAudio])
        #expect(OptionalAccess.systemAudio.settingsURL?.absoluteString.hasSuffix("Privacy_AudioCapture") == true)
        // Listed in Privacy only once a feature that needs it is in the build.
        #expect(SettingsSearch.optionalAccessEntries.isEmpty == !Feature.mixer.isBuilt)
    }
}
