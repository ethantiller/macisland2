import Foundation
import IOKit.pwr_mgt
import Testing

@testable import MacIsland

@MainActor
private final class StubAssertions: PowerAssertions {
    var refuses: Set<PowerAssertionKindKey> = []
    private(set) var live: [IOPMAssertionID: PowerAssertionKind] = [:]
    private var next: IOPMAssertionID = 100
    private(set) var created: [PowerAssertionKind] = []

    func create(_ kind: PowerAssertionKind, name: String) -> IOPMAssertionID? {
        created.append(kind)
        guard !refuses.contains(PowerAssertionKindKey(kind)) else { return nil }
        next += 1
        live[next] = kind
        return next
    }

    func release(_ id: IOPMAssertionID) { live[id] = nil }
    func exists(_ id: IOPMAssertionID) -> Bool { live[id] != nil }

    /// What the system does to an assertion when the Mac sleeps anyway.
    func dropAll() { live = [:] }
}

private struct PowerAssertionKindKey: Hashable {
    let isDisplay: Bool
    init(_ kind: PowerAssertionKind) { isDisplay = kind == .displaySleep }
}

@MainActor
struct KeepAwakeTests {
    private func make(_ stub: StubAssertions = StubAssertions()) -> (KeepAwake, StubAssertions) {
        (KeepAwake(assertions: stub, observesWake: false), stub)
    }

    @Test func itHoldsTheDisplayAndTheSystemAssertionAndReleasesBoth() {
        let (keepAwake, stub) = make()
        keepAwake.start(.indefinitely)
        #expect(keepAwake.isOn && Set(stub.live.values.map(PowerAssertionKindKey.init)).count == 2)
        #expect(stub.created == [.displaySleep, .systemSleep])
        keepAwake.stop()
        #expect(!keepAwake.isOn && stub.live.isEmpty)
    }

    @Test func changingTheDurationDoesNotMakeMoreAssertions() {
        let (keepAwake, stub) = make()
        keepAwake.start(.indefinitely)
        keepAwake.start(.hour)
        #expect(stub.created.count == 2 && keepAwake.duration == .hour)
    }

    @Test func aRefusedSystemAssertionStillLeavesItOnBecauseTheDisplayOneIsTheTool() {
        let stub = StubAssertions()
        stub.refuses = [PowerAssertionKindKey(.systemSleep)]
        let (keepAwake, _) = make(stub)
        keepAwake.start(.indefinitely)
        #expect(keepAwake.isOn && stub.live.count == 1)
    }

    @Test func aRefusedDisplayAssertionMeansItDidNotTurnOn() {
        let stub = StubAssertions()
        stub.refuses = [PowerAssertionKindKey(.displaySleep)]
        let (keepAwake, _) = make(stub)
        keepAwake.start(.indefinitely)
        #expect(!keepAwake.isOn && stub.live.isEmpty)
    }

    @Test func afterAWakeItIsOffIfTheSystemNoLongerHoldsTheAssertion() {
        let (keepAwake, stub) = make()
        keepAwake.start(.hour)
        keepAwake.reconcile()
        #expect(keepAwake.isOn, "still held: nothing changes")
        stub.dropAll()
        keepAwake.reconcile()
        #expect(!keepAwake.isOn && keepAwake.duration == .indefinitely, "never a stuck On")
        // Turning it on again works, and reconciling while off does nothing.
        keepAwake.reconcile()
        keepAwake.start(.indefinitely)
        #expect(keepAwake.isOn)
    }

    @Test func theToolSaysInWordsThatALidCanStillSleepIt() {
        #expect(KeepAwake.limits.contains("lid") && KeepAwake.limits.contains("external display"))
    }
}
