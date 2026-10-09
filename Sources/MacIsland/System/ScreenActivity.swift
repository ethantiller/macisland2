import AppKit
import Observation
import SwiftUI

/// Whether anyone can see the screen: false while it is locked, the display is asleep, or the screen saver runs. Things that only
/// exist to be looked at (a ticking clock, a poll for something to show) check it and rest until it is true again.
@MainActor
@Observable
final class ScreenActivity {
    static let shared = ScreenActivity()

    private(set) var isActive = true

    @ObservationIgnored private var locked = false
    @ObservationIgnored private var displayAsleep = false
    @ObservationIgnored private var saverRunning = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (ScreenActivity) -> Void) {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    change(self)
                    self.update()
                }
            }
            observers.append(observer)
        }
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.locked = true }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false }
        watch(distributed, Notification.Name("com.apple.screensaver.didstart")) { $0.saverRunning = true }
        watch(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.saverRunning = false }
    }

    private func update() {
        let active = !(locked || displayAsleep || saverRunning)
        if active != isActive { isActive = active }
    }
}

/// A `TimelineView` that stops ticking while nobody can see the screen, and shows the time as of the last tick.
struct Ticking<Content: View>: View {
    let interval: TimeInterval
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        if ScreenActivity.shared.isActive {
            TimelineView(.periodic(from: .now, by: interval)) { context in content(context.date) }
        } else {
            content(Date())
        }
    }
}
