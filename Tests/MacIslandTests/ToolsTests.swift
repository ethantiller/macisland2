import AppKit
import Testing

@testable import MacIsland

@MainActor
struct TimerModelTests {
    @Test func idleShowsFullDuration() {
        let timer = TimerModel()
        #expect(!timer.isActive)
        #expect(timer.remaining(at: Date()) == 300)
    }

    @Test func startCountsDown() {
        let timer = TimerModel()
        timer.start(minutes: 1)
        #expect(timer.isRunning)
        let remaining = timer.remaining(at: Date().addingTimeInterval(20))
        #expect(remaining > 39 && remaining <= 40)
        timer.reset()
    }

    @Test func pauseFreezesAndAddMinuteExtends() {
        let timer = TimerModel()
        timer.start(minutes: 1)
        timer.toggle()
        #expect(!timer.isRunning && timer.isActive)
        let paused = timer.remaining(at: Date())
        #expect(timer.remaining(at: Date().addingTimeInterval(30)) == paused)

        timer.addMinute()
        #expect(timer.remaining(at: Date()) == paused + 60)
        #expect(timer.duration == 120)
        timer.reset()
        #expect(!timer.isActive)
    }
}

@MainActor
struct SystemActionsTests {
    @Test func hexStringFromSRGB() {
        #expect(SystemActions.hexString(for: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) == "#FF0000")
        #expect(SystemActions.hexString(for: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)) == "#336699")
    }
}
