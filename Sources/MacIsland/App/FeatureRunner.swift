import Foundation

/// What a switch in the Features catalog starts and stops. A feature that is off has no background work: turning it off stops what it
/// runs (and what the person had running with it), turning it on starts what it needs again. The launch only starts what is on, and
/// asks for nothing. The parts that live in the app delegate (the adapter, the screenshot search) are closures, so this is tested with
/// counters.
@MainActor
final class FeatureRunner {
    private let features: IslandFeatures
    private let viewModel: IslandViewModel
    private let music: (Bool) -> Void
    private let screenshots: (Bool) -> Void

    init(
        features: IslandFeatures, viewModel: IslandViewModel, music: @escaping (Bool) -> Void,
        screenshots: @escaping (Bool) -> Void
    ) {
        self.features = features
        self.viewModel = viewModel
        self.music = music
        self.screenshots = screenshots
    }

    private var settings: AppSettings { features.settings }

    // MARK: What each setting means once the features are taken into account

    /// Reminders and calendar are read only while both their feature and their Up Next switch are on.
    static func configureAgenda(_ features: IslandFeatures, mayAsk: Bool) {
        let settings = features.settings
        features.agenda.configure(
            calendar: settings.showsCalendar, reminders: settings.showsReminders && settings.isOn(.reminders),
            mayAsk: mayAsk, showsTimeLeft: settings.showsTimeLeft, hiddenCalendars: settings.hiddenCalendars)
    }

    /// The city the weather follows: none while Weather is off (the city itself is kept).
    static func weatherCity(_ settings: AppSettings) -> String {
        settings.isOn(.weather) ? settings.weatherCity : ""
    }

    static func wantsLyrics(_ settings: AppSettings) -> Bool {
        settings.showsLyrics && settings.isOn(.music)
    }

    static func wantsScreenshots(_ settings: AppSettings) -> Bool {
        settings.addsScreenshots && settings.isOn(.shelf)
    }

    // MARK: Launch and changes

    /// At launch: starts only what is on, and prompts for nothing.
    func startAtLaunch() {
        if settings.isOn(.music) { music(true) }
        settings.syncHomeWidgets()
        viewModel.leaveModuleThatIsOff()
    }

    /// A feature was switched on or off.
    func apply(_ feature: Feature) {
        let on = settings.isOn(feature)
        switch feature {
        case .music:
            music(on)
            features.nowPlaying.lyrics.setEnabled(Self.wantsLyrics(settings), for: features.nowPlaying.state)
        case .clock:
            if !on {
                features.timer.reset()
                features.pomodoro.reset()
                features.stopwatch.reset()
            }
        case .reminders, .calendar:
            // Turning a feature on is the choice to be asked.
            Self.configureAgenda(features, mayAsk: true)
        case .tools:
            if !on { stopTools() }
        case .shelf:
            screenshots(Self.wantsScreenshots(settings))
        case .clipboard:
            features.clipboard.setCapacity(settings.effectiveClipboardLimit)
        case .notes:
            if !on, features.voice.isRecording {
                let voice = features.voice
                Task { await voice.stop() }  // saved, not lost
            }
        case .weather:
            features.weather.configure(city: Self.weatherCity(settings))
        case .volumeHUD, .agents, .mixer, .system, .downloads, .chooseActivity, .notifications:
            break  // `volumeHUD` follows its own setting; the rest arrive with their packages
        }
        viewModel.leaveModuleThatIsOff()
    }

    private func stopTools() {
        features.keepAwake.stop()
        if features.ringLight.isOn { features.ringLight.toggle() }
        features.mirror.stop()
        features.keyboardCleaner.unlock()
    }
}
