import AVFoundation
import AppKit
import CoreAudio

/// The island's features built from sample data, for the Settings preview. It reads the live `AppSettings`, so a
/// change applies at once, but everything else is the preview's own: nothing here reaches the network, the
/// calendar, a device, or the person's real Shelf and notes. `AppDelegate.makeFeatures` and `TestSupport` are its
/// twins, so a new feature touches all three.
@MainActor
enum PreviewFeatures {
    /// Where the preview keeps what it writes: a private defaults suite and a temp folder, both removed when the
    /// preview goes away.
    struct Scratch {
        let suiteName = "MacIslandSettingsPreview.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacIslandPreview-\(UUID().uuidString)")

        var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

        func remove() {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// `live` supplies the settings and the read-only system monitors (audio, power, microphone, network), which
    /// hold listeners that must not be created and dropped every time Settings opens.
    static func make(live: IslandFeatures, scratch: Scratch) -> IslandFeatures {
        let defaults = scratch.defaults
        let shelf = ShelfModel(
            defaults: defaults, ownedFolder: scratch.directory.appendingPathComponent("Shelf Results"))
        let work = WorkTracker()
        let notes = NotesModel(directory: scratch.directory.appendingPathComponent("Notes"))
        let note = notes.addNote()
        notes.setBody("Talking points\nOpen with the demo, then the numbers.", ofNote: note.id)

        let nowPlaying = NowPlayingModel(adapter: nil)
        nowPlaying.apply(PreviewSamples.track())

        let weather = WeatherModel()
        weather.typingPause = .zero
        weather.fetch = PreviewSamples.weatherResponse
        weather.configure(city: "Paris")

        let agenda = AgendaMonitor()
        agenda.showSample(
            PreviewSamples.nextEvent(), upcoming: PreviewSamples.upcoming(), reminders: PreviewSamples.reminders())
        agenda.showSampleCalendars(groups: PreviewSamples.calendarGroups(), eventDays: PreviewSamples.eventDays())

        return IslandFeatures(
            nowPlaying: nowPlaying,
            outputs: live.outputs,
            shelf: shelf,
            timer: TimerModel(),
            stopwatch: StopwatchModel(),
            keepAwake: KeepAwake(),
            ringLight: RingLight(),
            micMute: live.micMute,
            privacy: live.privacy,
            transfers: TransferMonitor(),
            network: live.network,
            settings: live.settings,
            agenda: agenda,
            focus: FocusMode(),
            clipboard: ClipboardHistory(),
            pomodoro: PomodoroModel(defaults: defaults, plan: { live.settings.pomodoroPlan }),
            work: work,
            weather: weather,
            fileTools: FileTools(
                shelf: shelf, work: work, recognizer: InertRecognizer(),
                pasteboard: NSPasteboard(name: NSPasteboard.Name(UUID().uuidString)),
                stagingRoot: scratch.directory.appendingPathComponent("Staging")
            ),
            notes: notes,
            keyboardCleaner: KeyboardCleaner(),
            bluetooth: BluetoothDevices(provider: InertBluetooth()),
            mirror: CameraMirror(provider: InertCamera()),
            screenRecorder: ScreenRecorder(recorder: InertScreen(), shelf: shelf),
            voice: VoiceRecorder(
                transcriber: InertTranscriber(), notes: notes, shelf: shelf,
                folder: scratch.directory.appendingPathComponent("Voice")),
            widgets: CustomWidgetValues(fetcher: SampleWidgetFetcher()),
            system: SystemModel(sampler: PreviewSystemSampler()),
            agents: PreviewSamples.agents(),
            mixer: PreviewSamples.mixer(defaults: defaults),
            downloads: PreviewSamples.downloads(in: scratch.directory.appendingPathComponent("Downloads")),
            notifications: PreviewSamples.notifications()
        )
    }
}

/// What the preview shows: a track, a forecast, a meeting.
/// Fixed readings for the Settings preview, so it never reads the Mac.
@MainActor
final class PreviewSystemSampler: SystemSampling {
    func start() {}
    func stop() {}
    func sample() -> SystemReading {
        SystemReading(
            cpu: 0.23, memoryUsed: 11 << 30, memoryTotal: 16 << 30, pressure: .normal, thermal: .nominal,
            battery: (percent: 82, onAC: false))
    }
}

enum PreviewSamples {
    /// The level the volume HUD shows in the preview.
    static let volume = VolumeLevel(fraction: 0.62, isMuted: false)
    /// And the brightness it shows beside it.
    static let brightness = 0.7

    static func track() -> NowPlayingState {
        var state = NowPlayingState()
        state.title = "Midnight City"
        state.artist = "M83"
        state.isPlaying = true
        state.playbackRate = 1
        state.duration = 243
        state.elapsedTime = 81
        state.timestamp = Date()
        state.artworkBase64 = artwork().base64EncodedString()
        return state
    }

    static func artwork() -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 120), flipped: false) { rect in
            NSGradient(colors: [
                NSColor(srgbRed: 0.10, green: 0.05, blue: 0.35, alpha: 1),
                NSColor(srgbRed: 0.85, green: 0.20, blue: 0.55, alpha: 1),
            ])?.draw(in: rect, angle: 60)
            return true
        }
        let tiff = image.tiffRepresentation ?? Data()
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) ?? Data()
    }

    /// A fixed Open-Meteo answer, so the preview never goes to the network.
    @Sendable static func weatherResponse(_ url: URL) async -> Data? {
        if url.host == "geocoding-api.open-meteo.com" {
            return Data(#"{"results":[{"name":"Paris","latitude":48.85,"longitude":2.35}]}"#.utf8)
        }
        return forecast()
    }

    /// The forecast the preview and the snapshots show: now, the next hours, and five days, in UTC so it never depends on
    /// the machine that draws it.
    static func forecast(now: Date = Date()) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let hourFormat = DateFormatter()
        hourFormat.locale = Locale(identifier: "en_US_POSIX")
        hourFormat.timeZone = calendar.timeZone
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH:00"
        let dayFormat = DateFormatter()
        dayFormat.locale = hourFormat.locale
        dayFormat.timeZone = calendar.timeZone
        dayFormat.dateFormat = "yyyy-MM-dd"
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let dayStart = calendar.startOfDay(for: now)
        let root: [String: Any] = [
            "utc_offset_seconds": 0,
            "current": ["temperature_2m": 18.4, "weather_code": 2, "is_day": 1],
            "hourly": [
                "time": (0..<6).map { hourFormat.string(from: hourStart.addingTimeInterval(Double($0) * 3600)) },
                "temperature_2m": [18.4, 19.0, 19.2, 18.1, 17.0, 15.3],
                "weather_code": [2, 2, 1, 0, 0, 1],
                "is_day": [1, 1, 1, 1, 1, 1],
            ],
            "daily": [
                "time": (0..<5).map { dayFormat.string(from: dayStart.addingTimeInterval(Double($0) * 86_400)) },
                "weather_code": [2, 3, 61, 1, 0],
                "temperature_2m_max": [24.0, 26.0, 19.0, 22.0, 25.0],
                "temperature_2m_min": [12.0, 13.0, 11.0, 10.0, 12.0],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
    }

    /// A few files in a folder of the preview's own, one still arriving, so the Shelf's Downloads mode has something to draw.
    @MainActor
    static func downloads(in folder: URL) -> DownloadsFolder {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        for (index, name) in ["Invoice March.pdf", "Photo.jpg", "Archive.zip", "Notes.txt", "Report.pdf.download"].enumerated() {
            let url = folder.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            try? FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-Double(index) * 60)], ofItemAtPath: url.path)
        }
        let downloads = DownloadsFolder(folder: folder)
        downloads.reload()
        return downloads
    }

    /// A few notifications in an inbox that listens to nothing, so the Notifications widget has something to draw.
    @MainActor
    static func notifications() -> NotificationMirror {
        let mirror = NotificationMirror(reader: NotificationReader(environment: .inert))
        let now = Date()
        let samples: [(String, String, String, String)] = [
            ("Messages", "Maya", "", "Are we still on for lunch?"),
            ("Calendar", "Design Review", "In 10 minutes", ""),
            ("Mail", "Receipt from Orchard", "Your order", "Thanks for shopping with us."),
            ("Reminders", "Call the bank", "", ""),
        ]
        for (index, sample) in samples.enumerated() {
            mirror.inbox.add(
                MirroredNotification(
                    id: "preview-\(index)", app: sample.0, title: sample.1, subtitle: sample.2, body: sample.3,
                    isPersistent: false, date: now.addingTimeInterval(-Double(index) * 240)))
        }
        return mirror
    }

    /// Four apps and a level, with nothing behind them: no process list and no tap. Access reads as given, so the panel draws.
    @MainActor
    static func mixer(defaults: UserDefaults) -> AppMixer {
        OptionalAccessRecord.record(.asked, for: .systemAudio, defaults: defaults)
        OptionalAccessRecord.record(.allowed, for: .systemAudio, defaults: defaults)
        let settings = AppSettings(defaults: defaults)
        settings.mixerLevels = ["com.spotify.client": 0.6, "com.apple.Safari": 1.5]
        let mixer = AppMixer(settings: settings, listing: PreviewAppList(), tapper: InertTapper(), defaults: defaults)
        mixer.start()
        return mixer
    }

    /// The tasks for the Agents module and the closed island: Claude Code's, Codex's, or both when `agent` is nil.
    @MainActor
    static func agents(for agent: AgentKind? = nil) -> AgentActivity {
        let activity = AgentActivity()
        activity.usage.show(usageSnapshot())
        seedTasks(in: activity, for: agent)
        return activity
    }

    /// Two sample tasks, one per tool, each with a title, tokens, and the context used. Replaces what was there.
    @MainActor
    static func seedTasks(in activity: AgentActivity, for agent: AgentKind?) {
        activity.clearTasks()
        let started = Date().addingTimeInterval(-252)
        func work(
            _ kind: AgentKind, session: String, project: String, model: String, title: String, tokens: AgentTokens,
            context: (used: Int, window: Int)
        ) {
            activity.ingest(
                AgentLogEvent(
                    kind: .turnStarted, sessionID: session, cwd: "/Users/you/code/\(project)", model: model, date: started,
                    prompt: title),
                agent: kind, session: session, announces: false)
            activity.ingest(
                AgentLogEvent(
                    kind: .activity, tokens: tokens, contextTokens: context.used, contextWindow: context.window),
                agent: kind, session: session, announces: false)
        }
        if agent != .codex {
            work(
                .claudeCode, session: "preview-claude", project: "island", model: "claude-opus-4-5-20251101",
                title: "Fix the volume HUD", tokens: AgentTokens(input: 4_000, output: 30_000, cacheRead: 150_000),
                context: (124_000, 200_000))
        }
        if agent != .claudeCode {
            work(
                .codex, session: "preview-codex", project: "site", model: "gpt-5-codex", title: "Add the stats view",
                tokens: AgentTokens(input: 6_000, output: 20_000, cacheRead: 70_000), context: (98_040, 258_000))
        }
    }

    /// Forty days of use and the plan limits of both tools, for the Usage and Stats modes and the Agents widget. Codex was used on other
    /// days and at other hours than Claude Code, so the filter visibly changes the map.
    @MainActor
    static func usageSnapshot(now: Date = Date()) -> AgentUsageSnapshot {
        let calendar = Calendar.current
        var snapshot = AgentUsageSnapshot()
        snapshot.generated = now
        let projects = ["island", "notes", "site"]
        let models = ["claude-opus-4-5-20251101", "claude-sonnet-4-5-20250929"]
        func note(_ agent: AgentKind, day: Int, hour: Int, requests: Int) {
            var hours = snapshot.hours["\(day)|\(agent.rawValue)"] ?? Array(repeating: 0, count: 24)
            hours[hour] += requests
            snapshot.hours["\(day)|\(agent.rawValue)"] = hours
        }
        for offset in 0..<40 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let day = UsageDay.key(date, calendar: calendar)
            let scale = 1 + (offset * 7) % 5
            if offset % 7 != 3 {
                snapshot.buckets.append(
                    UsageBucket(
                        day: day, agent: .claudeCode, model: models[offset % 2], project: projects[offset % 3],
                        tokens: AgentTokens(
                            input: 40_000 * scale, output: 90_000 * scale, cacheRead: 6_000_000 * scale, cacheWrite: 500_000 * scale),
                        requests: 30 * scale))
                note(.claudeCode, day: day, hour: 10, requests: 18 * scale)
                note(.claudeCode, day: day, hour: 21, requests: 12 * scale)
                let minutes = offset == 9 ? 20 * 60 : 25 + (offset * 37) % 240
                let last = date.timeIntervalSince1970
                snapshot.sessions.append(
                    AgentSession(
                        agent: .claudeCode, first: last - Double(minutes) * 60, last: last, requests: 30 * scale,
                        project: projects[offset % 3]))
            }
            if offset % 4 == 2 {
                snapshot.buckets.append(
                    UsageBucket(
                        day: day, agent: .codex, model: "gpt-5-codex", project: "site",
                        tokens: AgentTokens(input: 20_000 * scale, output: 40_000 * scale, cacheRead: 2_000_000 * scale),
                        requests: 14 * scale))
                note(.codex, day: day, hour: 15, requests: 14 * scale)
                let last = date.timeIntervalSince1970
                snapshot.sessions.append(
                    AgentSession(agent: .codex, first: last - 45 * 60, last: last, requests: 14 * scale, project: "site"))
            }
        }
        snapshot.hasClaudePlanFile = true
        snapshot.limits = [
            AgentLimit(
                agent: .claudeCode, kind: .session, percent: 64, resetsAt: now.addingTimeInterval(2 * 3600 + 600), asOf: nil),
            AgentLimit(
                agent: .claudeCode, kind: .week, percent: 41, resetsAt: now.addingTimeInterval(3 * 86_400), asOf: nil),
            AgentLimit(
                agent: .codex, kind: .session, percent: 22, resetsAt: now.addingTimeInterval(3 * 3600), asOf: nil),
            AgentLimit(
                agent: .codex, kind: .week, percent: 12, resetsAt: now.addingTimeInterval(4 * 86_400), asOf: nil),
        ]
        return snapshot
    }

    static func nextEvent() -> AgendaItem {
        AgendaItem(
            id: "preview-event", kind: .event, title: "Design review",
            date: Date().addingTimeInterval(25 * 60), reminderID: nil, joinURL: nil,
            end: Date().addingTimeInterval(85 * 60))
    }

    /// Two accounts, for Settings' list of calendars.
    static func calendarGroups() -> [CalendarGroup] {
        [
            CalendarGroup(
                id: "preview-icloud", title: "iCloud",
                calendars: [.init(id: "preview-home", title: "Home"), .init(id: "preview-work", title: "Work")]),
            CalendarGroup(id: "preview-google", title: "Google", calendars: [.init(id: "preview-sam", title: "Sam")]),
        ]
    }

    /// A few days of this month with events, for the dots in the month view.
    static func eventDays() -> [Int: [AgendaItem]] {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: Date())
        func item(_ title: String, hour: Int) -> AgendaItem {
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            return AgendaItem(
                id: "preview-\(title)", kind: .event, title: title, date: start, end: start.addingTimeInterval(3600))
        }
        return [today: [item("Design review", hour: 10)], min(today + 3, 28): [item("Lunch with Sam", hour: 12)]]
    }

    /// The next few things, for Today at its taller sizes; the first is `nextEvent()`.
    static func upcoming() -> [AgendaItem] {
        [
            nextEvent(),
            AgendaItem(
                id: "preview-lunch", kind: .event, title: "Lunch with Sam", date: Date().addingTimeInterval(2 * 3600),
                reminderID: nil, joinURL: nil),
            AgendaItem(
                id: "preview-bank", kind: .reminder, title: "Call the bank", date: Date().addingTimeInterval(4 * 3600),
                reminderID: nil, joinURL: nil),
        ]
    }

    /// Open reminders, for Reminders at its taller sizes.
    static func reminders() -> [ReminderRow] {
        let now = Date()
        return [
            ReminderRow(id: "preview-mom", title: "Call Mom", due: now.addingTimeInterval(3 * 3600), hasTime: true),
            ReminderRow(id: "preview-rent", title: "Pay rent", due: now.addingTimeInterval(26 * 3600), hasTime: false),
            ReminderRow(id: "preview-food", title: "Buy groceries", due: nil, hasTime: false),
            ReminderRow(id: "preview-trip", title: "Book flights", due: nil, hasTime: false),
        ]
    }

    /// The banner the Notifications pane shows when nothing more specific is selected.
    @MainActor static func banner() -> IslandBanner {
        Announcements.headphones(AudioAccessory(name: "AirPods Pro", left: 82, right: 80, caseLevel: 64))
    }
}

// MARK: Inert doubles

/// Reads nothing.
struct InertRecognizer: TextRecognizing {
    func recognize(_ image: CGImage) async throws -> RecognizedText {
        RecognizedText(lines: [], barcodePayloads: [])
    }
}

@MainActor
final class InertBluetooth: BluetoothDeviceProviding {
    func pairedAudioDevices() -> [PairedDevice] { [] }
    func connect(_ id: String) async -> Bool { false }
    func disconnect(_ id: String) {}
}

@MainActor
final class InertCamera: CameraSessionProviding {
    var access: CameraAccess { .denied }
    func requestAccess() async -> Bool { false }
    func start() async throws -> AVCaptureSession { throw CameraError.noCamera }
    func stop() {}
}

@MainActor
final class InertScreen: ScreenRecording {
    var hasAccess: Bool { false }
    func requestAccess() -> Bool { false }
    func start(region: CGRect?, on display: CGDirectDisplayID) async throws { throw CameraError.noCamera }
    func stop() async throws -> URL { throw CameraError.noCamera }
}

@MainActor
final class InertTranscriber: Transcribing {
    var level: Float { 0 }
    func start(writingTo file: URL) async throws { throw VoiceError.microphoneDenied }
    func stop() async throws -> String { "" }
}

/// The Settings preview's apps: fixed, so it never reads the Mac's audio.
@MainActor
final class PreviewAppList: AppAudioListing {
    var onChange: (() -> Void)?
    func start() {}
    func stop() {}
    func current() -> [MixerApp] {
        [
            MixerApp(id: "com.apple.Music", name: "Music", processObjects: [1], isPlaying: true),
            MixerApp(id: "com.spotify.client", name: "Spotify", processObjects: [2], isPlaying: true),
            MixerApp(id: "com.apple.Safari", name: "Safari", processObjects: [3], isPlaying: true),
            MixerApp(id: "us.zoom.xos", name: "zoom.us", processObjects: [4], isPlaying: true),
        ]
    }
}

/// Makes taps that do nothing, and hear sound, so the preview's Mixer never changes how anything sounds.
@MainActor
final class InertTapper: AudioTapping {
    private final class Tap: AudioTap {
        var heardSound: Bool { true }
        func setLevel(_ level: Float) {}
        func stop() {}
    }

    func start(processObjects: [AudioObjectID], outputUID: String?, level: Float) -> AudioTap? { Tap() }
    func probe() async {}
}
