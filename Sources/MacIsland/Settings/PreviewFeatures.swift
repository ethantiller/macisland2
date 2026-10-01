import AVFoundation
import AppKit

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
            widgets: CustomWidgetValues(fetcher: SampleWidgetFetcher())
        )
    }
}

/// What the preview shows: a track, a forecast, a meeting.
enum PreviewSamples {
    /// The level the volume HUD shows in the preview.
    static let volume = VolumeLevel(fraction: 0.62, isMuted: false)

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

    static func nextEvent() -> AgendaItem {
        AgendaItem(
            id: "preview-event", kind: .event, title: "Design review",
            date: Date().addingTimeInterval(25 * 60), reminderID: nil, joinURL: nil)
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
