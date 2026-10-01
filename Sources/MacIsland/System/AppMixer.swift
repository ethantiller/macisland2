import AppKit
import CoreAudio
import Foundation
import Observation

/// One app in the Mixer's panel.
struct MixerRow: Identifiable, Equatable {
    var id: String
    var name: String
    var isPlaying: Bool
    var isNeverTapped: Bool
}

/// Per-app volume (0 to 200%) and output, with no driver: an app that is adjusted is tapped and played again by MacIsland, and an app
/// that is not is not touched.
///
/// **A tap only when needed.** An app at 100% on the default output has no tap. An adjusted app has one only while it is running
/// output; when it stops, the tap and its device are gone (no IO), and they are made again when output starts. With nothing adjusted,
/// the Mixer costs only its listeners.
///
/// **Permission.** System Audio Recording has no API to ask about. Nothing taps at launch unless it is already `allowed`; the person
/// answers from the Features pane (`OptionalAccess.systemAudio`), and after that the first adjustment taps. A tap that cannot be made,
/// or that hears only silence for two seconds while its app is playing, marks it `denied` and **tears every tap down at once**, so a
/// muted-when-tapped app is never left silent. Sound through a tap marks it `allowed`.
@MainActor
@Observable
final class AppMixer {
    /// Calls and pro-audio apps stay as they are: where latency matters, the Mixer keeps its hands off. Kept as bundle IDs.
    nonisolated static let neverTappedBundleIDs: Set<String> = [
        // Calls.
        "us.zoom.xos", "com.apple.FaceTime", "com.microsoft.teams", "com.microsoft.teams2", "com.apple.TelephonyUtilities",
        // Pro audio.
        "com.apple.logic10", "com.apple.garageband10", "com.apple.mainstage3", "com.ableton.live", "com.avid.ProTools",
        "com.cockos.reaper", "com.steinberg.cubase", "com.presonus.StudioOne", "com.bitwig.BitwigStudio",
        "com.image-line.flstudio",
    ]

    nonisolated static func neverTapped(bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier || neverTappedBundleIDs.contains(bundleID)
            || neverTappedBundleIDs.contains { bundleID.hasPrefix($0 + ".") }
    }

    static let range = 0.0...2.0

    /// The apps that make sound or have been adjusted, in the order Core Audio lists them.
    private(set) var apps: [MixerApp] = []
    /// Non-default levels, by bundle ID (kept in Settings, and exported with them).
    var levels: [String: Double] { settings.mixerLevels }
    /// Chosen outputs by bundle ID, as device UIDs. They belong to this Mac and stay out of the settings file.
    var outputs: [String: String] { settings.mixerOutputs }
    private(set) var isRunning = false
    /// Where the permission stands, for the panel.
    private(set) var access: OptionalAccessState

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let listing: AppAudioListing
    @ObservationIgnored private let tapper: AudioTapping
    @ObservationIgnored private let defaults: UserDefaults
    /// The UIDs of the outputs that exist now, and the default's.
    @ObservationIgnored var availableOutputs: () -> Set<String> = { [] }
    @ObservationIgnored var defaultOutput: () -> String? = { nil }
    @ObservationIgnored var silenceDelay: Duration = .seconds(2)
    @ObservationIgnored private var taps: [String: (tap: AudioTap, output: String?)] = [:]
    /// Whether the person has adjusted something since the Mixer started: a permission that can't be checked is trusted after that.
    @ObservationIgnored private var hasActed = false

    init(settings: AppSettings, listing: AppAudioListing, tapper: AudioTapping, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.listing = listing
        self.tapper = tapper
        self.defaults = defaults
        access = OptionalAccessRecord.state(of: .systemAudio, defaults: defaults)
        listing.onChange = { [weak self] in self?.reconcile() }
    }

    /// For tests: the apps that have a tap now.
    var tappedApps: Set<String> { Set(taps.keys) }

    // MARK: Start and stop

    func start() {
        guard !isRunning else { return }
        isRunning = true
        hasActed = false
        access = OptionalAccessRecord.state(of: .systemAudio, defaults: defaults)
        listing.start()
        apps = listing.current()
        reconcile()
    }

    /// Off: every tap and device is given back, and the listeners stop.
    func stop() {
        isRunning = false
        tearDown()
        listing.stop()
        apps = []
    }

    /// Gives every app's sound back.
    func tearDown() {
        for (_, entry) in taps { entry.tap.stop() }
        taps = [:]
    }

    /// The output devices changed (one went away, or the default did): taps are made again against what exists now.
    func devicesChanged() {
        guard isRunning else { return }
        tearDown()
        reconcile()
    }

    // MARK: What the panel lists

    /// The apps that are playing, and those that have been adjusted (so a level can be set between songs): playing first, by name.
    var rows: [MixerRow] {
        guard isRunning else { return [] }
        let adjusted = Set(levels.keys).union(outputs.keys)
        var result = apps.filter { $0.isPlaying || adjusted.contains($0.id) }
            .map { MixerRow(id: $0.id, name: $0.name, isPlaying: $0.isPlaying, isNeverTapped: $0.isNeverTapped) }
        let listed = Set(result.map(\.id))
        result += adjusted.subtracting(listed).map {
            MixerRow(id: $0, name: Self.displayName(for: $0), isPlaying: false, isNeverTapped: false)
        }
        return result.sorted { ($0.isPlaying ? 0 : 1, $0.name.lowercased()) < ($1.isPlaying ? 0 : 1, $1.name.lowercased()) }
    }

    /// An app's name from its bundle ID, for an adjusted app that isn't running.
    static func displayName(for bundleID: String) -> String {
        if let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    // MARK: Levels and outputs

    /// A slider's level: a drag that ends this close to 100% lands on it.
    static func snapped(_ level: Double) -> Double { abs(level - 1) < 0.04 ? 1 : level }

    func level(for id: String) -> Double { levels[id] ?? 1 }

    /// The chosen output's UID, or nil for the default. A device that is gone counts as the default.
    func output(for id: String) -> String? {
        guard let uid = outputs[id], availableOutputs().contains(uid), uid != defaultOutput() else { return nil }
        return uid
    }

    /// What the person chose, even if that device is not there now.
    func chosenOutput(for id: String) -> String? { outputs[id] }

    func setLevel(_ level: Double, for id: String) {
        guard !Self.neverTapped(bundleID: id) else { return }
        let clamped = min(max(level, Self.range.lowerBound), Self.range.upperBound)
        let value = abs(clamped - 1) < 0.005 ? 1 : clamped
        guard value != self.level(for: id) else { return }
        if value == 1 { settings.mixerLevels[id] = nil } else { settings.mixerLevels[id] = value }
        hasActed = true
        reconcile()
    }

    /// While a slider is dragged: the running tap follows at once, and nothing is stored until the level is committed.
    func previewLevel(_ level: Double, for id: String) {
        guard !Self.neverTapped(bundleID: id) else { return }
        taps[id]?.tap.setLevel(Float(min(max(level, Self.range.lowerBound), Self.range.upperBound)))
    }

    func setOutput(_ uid: String?, for id: String) {
        guard !Self.neverTapped(bundleID: id), outputs[id] != uid else { return }
        settings.mixerOutputs[id] = uid
        hasActed = true
        reconcile()
    }

    /// Back to 100% on the default output.
    func reset(_ id: String) {
        setLevel(1, for: id)
        setOutput(nil, for: id)
    }

    // MARK: Which apps are tapped

    /// Whether an app's sound should go through a tap now.
    func wantsTap(_ app: MixerApp) -> Bool {
        guard isRunning, canTap, app.isPlaying, !app.isNeverTapped else { return false }
        return level(for: app.id) != 1 || output(for: app.id) != nil
    }

    /// Whether the permission lets a tap be made. At launch only an answer already seen counts; once the person has adjusted something
    /// after pressing Allow, an answer that can't be checked is trusted until a tap proves it wrong.
    private var canTap: Bool {
        switch access {
        case .allowed: true
        case .asked: hasActed
        case .notAsked, .denied: false
        }
    }

    /// Makes the taps match what is wanted: starts those that are, stops those that are not, and follows a change of level or output.
    func reconcile() {
        guard isRunning else {
            tearDown()
            return
        }
        let listed = listing.current()
        if listed != apps { apps = listed }
        let state = OptionalAccessRecord.state(of: .systemAudio, defaults: defaults)
        if state != access { access = state }
        var live: Set<String> = []
        for app in apps {
            guard wantsTap(app) else { continue }
            live.insert(app.id)
            let output = output(for: app.id)
            if let entry = taps[app.id] {
                if entry.output == output {
                    entry.tap.setLevel(Float(level(for: app.id)))
                    continue
                }
                entry.tap.stop()
                taps[app.id] = nil
            }
            guard start(app, output: output) else { return }
        }
        for id in Array(taps.keys) where !live.contains(id) {
            taps[id]?.tap.stop()
            taps[id] = nil
        }
    }

    /// False if the permission failed and every tap was torn down.
    private func start(_ app: MixerApp, output: String?) -> Bool {
        guard let tap = tapper.start(processObjects: app.processObjects, outputUID: output, level: Float(level(for: app.id))) else {
            failed()
            return false
        }
        taps[app.id] = (tap, output)
        checkForSound(of: app.id, tap: tap)
        return true
    }

    /// Two seconds after a tap starts: sound through it means the permission is given; silence while its app still plays means it is not.
    private func checkForSound(of id: String, tap: AudioTap) {
        let delay = silenceDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.isRunning, let entry = self.taps[id], entry.tap === tap else { return }
            if tap.heardSound {
                OptionalAccessRecord.record(.allowed, for: .systemAudio, defaults: self.defaults)
                self.access = OptionalAccessRecord.state(of: .systemAudio, defaults: self.defaults)
            } else if self.access != .allowed, self.apps.first(where: { $0.id == id })?.isPlaying == true {
                self.failed()
            }
        }
    }

    /// The permission is off: nothing stays tapped.
    private func failed() {
        tearDown()
        if access != .allowed {
            OptionalAccessRecord.record(.denied, for: .systemAudio, defaults: defaults)
            access = OptionalAccessRecord.state(of: .systemAudio, defaults: defaults)
        }
    }
}
