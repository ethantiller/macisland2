import SwiftUI

extension CompactActivity {
    /// Banners and alerts always come first, and nothing is chosen between them.
    var isChoosable: Bool {
        switch self {
        case .banner, .alert, .none: false
        default: true
        }
    }

    /// Which activity this is, across the changes inside it (a new job title is still the same job).
    var choiceID: String {
        switch self {
        case .banner: "banner"
        case .alert: "alert"
        case .recording(let kind): kind == .screen ? "recording.screen" : "recording.voice"
        case .microphone: "microphone"
        case .timer: "timer"
        case .pomodoro: "pomodoro"
        case .stopwatch: "stopwatch"
        case .countdown: "countdown"
        case .working: "working"
        case .agent: "agent"
        case .transfer: "transfer"
        case .media: "media"
        case .keepAwake: "keepAwake"
        case .none: "none"
        }
    }

    /// What its chip in the peek says.
    var title: String {
        switch self {
        case .banner, .alert, .none: ""
        case .recording(let kind): kind == .screen ? "Screen Recording" : "Voice Note"
        case .microphone: "Microphone"
        case .timer: "Timer"
        case .pomodoro: "Pomodoro"
        case .stopwatch: "Stopwatch"
        case .countdown: "Countdown"
        case .working(let job): job
        case .agent: "Agents"
        case .transfer: "Download"
        case .media: "Music"
        case .keepAwake: "Keep Awake"
        }
    }
}

extension IslandViewModel {
    /// The live activities a person can choose between: all but banners and alerts.
    var choosableActivities: [CompactActivity] { compactActivities.filter(\.isChoosable) }

    /// The peek's row of choices: only with the feature on and two or more things live.
    var showsActivityChoice: Bool {
        features.settings.isOn(.chooseActivity) && choosableActivities.count >= 2
    }

    func chooseActivity(_ activity: CompactActivity) {
        guard activity.isChoosable, chosenActivityID != activity.choiceID else { return }
        withAnimation(Theme.Motion.resize) { chosenActivityID = activity.choiceID }
    }

    /// The choice ends with its activity, so a later one of the same kind starts in its usual place.
    func pruneChosenActivity() {
        guard let chosen = chosenActivityID else { return }
        if !features.settings.isOn(.chooseActivity) || !liveActivities.contains(where: { $0.choiceID == chosen }) {
            chosenActivityID = nil
        }
    }
}

/// A row of the live activities at the top of the peek, the leading one selected.
struct ActivityChoiceRow: View {
    let viewModel: IslandViewModel

    var body: some View {
        let activities = viewModel.choosableActivities
        let leading = activities.first?.choiceID
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(activities, id: \.choiceID) { activity in
                    ChipButton(
                        title: activity.title, isSelected: activity.choiceID == leading,
                        accessibilityLabel: "Show \(activity.title)"
                    ) {
                        viewModel.chooseActivity(activity)
                    }
                }
            }
        }
        .frame(height: Theme.Metrics.hitTarget)
    }
}
