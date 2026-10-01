import SwiftUI

/// The Clock module's options: the Pomodoro's lengths. The preview shows the Clock tab on Pomodoro, so a change is seen on its ring.
struct ClockOptions: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    var body: some View {
        Group {
            Section {
                SettingsDropdown(
                    title: "Focus Length", selection: Bindable(settings).pomodoroFocus,
                    options: Self.minuteOptions(
                        [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 75, 90], current: settings.pomodoroFocus)
                )
                .tourAnchor(.pomodoro)
                SettingsDropdown(
                    title: "Short Break", selection: Bindable(settings).pomodoroShortBreak,
                    options: Self.minuteOptions(
                        [1, 2, 3, 5, 7, 10, 15, 20, 25, 30], current: settings.pomodoroShortBreak))
                SettingsDropdown(
                    title: "Long Break", selection: Bindable(settings).pomodoroLongBreak,
                    options: Self.minuteOptions(
                        [5, 10, 15, 20, 25, 30, 40, 45, 60], current: settings.pomodoroLongBreak))
                SettingsDropdown(
                    title: "Sessions Before Long Break", selection: Bindable(settings).pomodoroSessions,
                    options: DropdownOption.all(Array(PomodoroPlan.sessionsRange)) { "\($0)" })
            } header: {
                Text("Pomodoro").id(SettingsAnchor.pomodoro)
            } footer: {
                Text(
                    "A phase that is running keeps its length; a change applies from the next one. Changing the sessions counts the cycle under way against the new number."
                )
            }
        }
        .onAppear { preview?.show(TabsPane.previewContext(for: .clock)) }
    }

    /// The usual choices, plus the current value when it is not one of them (a number from an imported file).
    static func minuteOptions(_ usual: [Int], current: Int) -> [DropdownOption<Int>] {
        Set(usual + [current]).sorted().map { DropdownOption($0, $0 == 1 ? "1 minute" : "\($0) minutes") }
    }
}
