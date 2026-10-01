import Foundation
import Observation

/// Where the first-run guide and the Settings tour stand: which version each one last ran to its end, and whether this
/// install was already in use before they existed.
///
/// Not part of `AppSettings`: that holds personal choices, and this is history. It is also shared with the Settings
/// preview and rewritten by Import and Reset All, and onboarding progress must survive both.
@MainActor
@Observable
final class OnboardingState {
    enum Install: String {
        /// Nothing from an earlier run was found. Shown the guide and the tour.
        case fresh
        /// MacIsland ran here before this code existed. Shown neither; both can be replayed.
        case existing
    }

    /// Bump to show the guide again to everyone who saw an older one. Only steps with a newer `since` are shown on a re-run.
    nonisolated static let guideVersion = 1
    /// The same for the Settings tour, stop by stop.
    nonisolated static let tourVersion = 1

    /// How this install was classified. Decided once, on the first launch that has this code, and trusted after.
    private(set) var install: Install
    /// The guide version last completed. 0 is never.
    private(set) var guideSeen: Int
    /// The tour version last completed or ended. 0 is never.
    private(set) var tourSeen: Int
    /// In memory only. Replay, the guide's Open Settings, and `macisland://tour` set it; `SettingsView` starts the tour and clears it.
    var tourRequested = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let currentGuide: Int
    @ObservationIgnored private let currentTour: Int

    private enum Key {
        static let install = "onboarding.install"
        static let guide = "onboarding.guide"
        static let tour = "onboarding.settingsTour"
        static let resumeStep = "onboarding.resumeStep"
    }

    /// `isExistingInstall` is only asked when no classification is stored yet. It has to run before anything in this launch
    /// writes a setting, so `AppDelegate` creates this first.
    init(
        defaults: UserDefaults = .standard,
        isExistingInstall: @MainActor () -> Bool = InstallEvidence.live,
        guideVersion: Int = OnboardingState.guideVersion,
        tourVersion: Int = OnboardingState.tourVersion
    ) {
        self.defaults = defaults
        currentGuide = guideVersion
        currentTour = tourVersion
        // Locals first: an `@Observable` property can't be read before every stored property is set.
        let classified: Install
        if let stored = defaults.string(forKey: Key.install).flatMap(Install.init) {
            classified = stored
        } else {
            // A fresh user who quits mid-guide leaves evidence behind (every clean quit writes the notes file), so
            // this is written once and never derived again.
            classified = isExistingInstall() ? .existing : .fresh
            defaults.set(classified.rawValue, forKey: Key.install)
            if classified == .existing {
                defaults.set(guideVersion, forKey: Key.guide)
                defaults.set(tourVersion, forKey: Key.tour)
            }
        }
        install = classified
        guideSeen = defaults.integer(forKey: Key.guide)
        tourSeen = defaults.integer(forKey: Key.tour)
    }

    /// The step the guide was on when MacIsland quit, so a relaunch (Screen Recording asks for one) or a quit from the menu bar
    /// picks it up there. Cleared when the guide ends.
    var resumeStep: GuideStepID? {
        get { defaults.string(forKey: Key.resumeStep).flatMap(GuideStepID.init(rawValue:)) }
        set {
            if let newValue { defaults.set(newValue.rawValue, forKey: Key.resumeStep) } else { defaults.removeObject(forKey: Key.resumeStep) }
        }
    }

    var needsGuide: Bool { guideSeen < currentGuide }
    var needsTour: Bool { tourSeen < currentTour }

    /// The guide ended by Done or Open Settings. Writes only when something changes.
    func finishGuide() {
        guard guideSeen < currentGuide else { return }
        guideSeen = currentGuide
        defaults.set(currentGuide, forKey: Key.guide)
    }

    /// The tour ended, by its last stop, End Tour, or the window closing. Writes only when something changes.
    func finishTour() {
        guard tourSeen < currentTour else { return }
        tourSeen = currentTour
        defaults.set(currentTour, forKey: Key.tour)
    }

    #if DEBUG
        /// Puts this install back to a fresh one, for `macisland://guide?reset=1`.
        func resetToFresh() {
            install = .fresh
            guideSeen = 0
            tourSeen = 0
            defaults.set(Install.fresh.rawValue, forKey: Key.install)
            defaults.set(0, forKey: Key.guide)
            defaults.set(0, forKey: Key.tour)
            defaults.removeObject(forKey: Key.resumeStep)
        }
    #endif
}

/// Signs that MacIsland ran here before this code existed: keys only a used install has, and the notes file every clean
/// quit writes.
///
/// `AppSettings.Key` is private, so the keys are listed here and a test (`evidenceKeysCoverEverySetting`) fails when a
/// setting is stored under a key that isn't. A new setting that isn't listed would make an updater look like a fresh install.
enum InstallEvidence {
    static let keys: [String] = [
        // `AppSettings.Key`.
        "tabs", "tabsLeft", "tabsRight", "menuBarModules", "hotkey", "shortcut.open", "peeksOnHover", "swipesEnabled",
        "islandDisplay", "mutedEvents", "dragTarget", "addsScreenshots", "shelfRetention", "clipboardLimit", "shelfMode",
        "showsMusicCompact", "quietDuringFocus", "showsCalendar", "showsReminders", "pinLimit", "fullChargeLevel",
        "showsLyrics", "replacesVolumeHUD", "pomodoroFocus", "pomodoroShortBreak", "pomodoroLongBreak", "pomodoroSessions", "weatherCity",
        "pinnedTools", "tools.shortcuts", "home.layout", "home.savedPresets", "widgets.custom",
        // Stored elsewhere.
        "shelf.paths", "shelf.added", "pomodoro.history", "settings.pane", "settings.sidebarHidden",
        // AppKit's frame autosave for `SettingsWindowController.frameName`.
        "NSWindow Frame MacIslandSettings",
    ]

    /// Any evidence key is set, or the notes file exists. Not "any key in the domain": the system writes its own keys into an
    /// app's domain (status item positions, panel directories), which would make a fresh install look used.
    static func isExisting(defaults: UserDefaults, notesFile: URL, fileExists: (URL) -> Bool) -> Bool {
        keys.contains { defaults.object(forKey: $0) != nil } || fileExists(notesFile)
    }

    /// This Mac's own defaults and notes file.
    @MainActor
    static func live() -> Bool {
        isExisting(
            defaults: .standard, notesFile: NotesModel.defaultFileURL,
            fileExists: { FileManager.default.fileExists(atPath: $0.path) })
    }
}
