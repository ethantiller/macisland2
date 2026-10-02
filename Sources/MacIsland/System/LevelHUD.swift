import AppKit
import AudioToolbox
import CoreAudio
import Observation

// A volume and brightness HUD of MacIsland's own, in place of the system's. The system draws its HUD for these keys itself, so the only
// way to replace it is to take the keys first: an event tap (Accessibility) consumes the media key, sets the volume through CoreAudio or
// the brightness through DisplayServices, and the island shows its own indicator. See docs/plans/volume-hud.md.

// MARK: The keys and the math

/// The media keys this handles. The values are `NX_KEYTYPE_*`.
enum MediaKey: Int, Equatable {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// What the HUD is asked to show: a volume (with its mute) or a brightness fraction.
enum LevelReading: Equatable {
    case volume(VolumeLevel)
    case brightness(Double)
}

enum LevelKind: Hashable {
    case volume, brightness
}

extension LevelReading {
    var kind: LevelKind {
        switch self {
        case .volume: .volume
        case .brightness: .brightness
        }
    }
}

/// The step math both levels share.
enum LevelStep {
    /// The system's levels have 16 steps, and Option and Shift together make a quarter of one.
    static let steps = 16.0
    static let quarterSteps = 64.0

    /// The next step from `fraction`: from the nearest one, so a level set by a slider lands on the grid.
    static func step(_ fraction: Double, up: Bool, quarter: Bool) -> Double {
        let size = 1 / (quarter ? quarterSteps : steps)
        let nearest = (fraction / size).rounded() * size
        return up ? min(nearest + size, 1) : max(nearest - size, 0)
    }
}

/// What the volume is: a level from 0 to 1, and whether it is muted.
struct VolumeLevel: Equatable {
    var fraction: Double
    var isMuted: Bool

    /// What the HUD shows: nothing is filled while muted.
    var shown: Double { isMuted ? 0 : fraction }
    /// Muted, or at zero: the two cases the HUD draws in color.
    var isSilent: Bool { isMuted || fraction <= 0 }

    /// The speaker for this level: slashed when silent, then one, two, or three waves.
    var symbol: String {
        if isSilent { return "speaker.slash.fill" }
        switch fraction {
        case ..<(1.0 / 3): return "speaker.wave.1.fill"
        case ..<(2.0 / 3): return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var percent: Int { Int((shown * 100).rounded()) }
}

enum VolumeStep {
    static let steps = LevelStep.steps
    static let quarterSteps = LevelStep.quarterSteps

    /// What a key does to `current`: up and down move to the next step, either also unmutes, and mute toggles.
    static func apply(_ key: MediaKey, to current: VolumeLevel, quarter: Bool = false) -> VolumeLevel {
        switch key {
        case .volumeUp: VolumeLevel(fraction: LevelStep.step(current.fraction, up: true, quarter: quarter), isMuted: false)
        case .volumeDown: VolumeLevel(fraction: LevelStep.step(current.fraction, up: false, quarter: quarter), isMuted: false)
        case .mute: VolumeLevel(fraction: current.fraction, isMuted: !current.isMuted)
        case .brightnessUp, .brightnessDown: current
        }
    }
}

/// One media key press, as the tap reads it.
struct MediaKeyEvent: Equatable {
    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    /// Option and Shift held together: a quarter step.
    let isQuarterStep: Bool
}

enum KeyDisposition: Equatable {
    /// The HUD took the key: nothing else sees it, and the system draws no HUD.
    case consume
    /// Not ours this time: the system handles it, with its own HUD.
    case passThrough
}

// MARK: The volume

/// The default output device's volume and mute.
@MainActor
protocol SystemVolume: AnyObject {
    /// Whether the default output can be set at all. An HDMI or DisplayPort output, and some Bluetooth ones, cannot; the system
    /// handles those keys itself.
    var canSetVolume: Bool { get }
    func read() -> VolumeLevel?
    func write(_ level: VolumeLevel) -> Bool
}

/// CoreAudio on the default output device: the virtual main volume if it has one, then the main element, then channels 1 and 2.
@MainActor
final class CoreAudioVolume: SystemVolume {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private var device: AudioDeviceID? {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(Self.system, &address, 0, nil, &size, &id) == noErr,
            id != AudioDeviceID(kAudioObjectUnknown)
        else { return nil }
        return id
    }

    var canSetVolume: Bool {
        guard let device else { return false }
        return volumeElements(of: device).contains { isSettable(device, $0) }
    }

    func read() -> VolumeLevel? {
        guard let device else { return nil }
        let elements = volumeElements(of: device)
        let values = elements.compactMap { float(device, $0) }
        guard !values.isEmpty else { return nil }
        let muted = uint(device, Self.muteAddress) == 1
        return VolumeLevel(fraction: Double(values.reduce(0, +)) / Double(values.count), isMuted: muted)
    }

    func write(_ level: VolumeLevel) -> Bool {
        guard let device else { return false }
        var ok = false
        for address in volumeElements(of: device) where isSettable(device, address) {
            var value = Float32(level.fraction)
            var address = address
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr {
                ok = true
            }
        }
        var mute = Self.muteAddress
        if AudioObjectHasProperty(device, &mute), isSettable(device, mute) {
            var value: UInt32 = level.isMuted ? 1 : 0
            AudioObjectSetPropertyData(device, &mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
        return ok
    }

    // MARK: Properties

    private static var muteAddress: AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    }

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// The addresses that hold this device's volume: the virtual main volume when there is one, else the main element, else each channel.
    private func volumeElements(of device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let scope = kAudioDevicePropertyScopeOutput
        let virtual = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)
        let main = Self.address(kAudioDevicePropertyVolumeScalar, scope: scope)
        var candidates = [virtual, main]
        for channel in [AudioObjectPropertyElement(1), 2] {
            candidates.append(Self.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: channel))
        }
        let present = candidates.filter { address in
            var address = address
            return AudioObjectHasProperty(device, &address)
        }
        // The first two are whole-device answers; channels are only used when neither exists.
        if let whole = present.first(where: { $0.mElement == kAudioObjectPropertyElementMain }) { return [whole] }
        return present
    }

    private func isSettable(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func float(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func uint(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}

// MARK: The brightness

/// The built-in display's brightness.
@MainActor
protocol DisplayBrightness: AnyObject {
    /// Whether the built-in display can be set at all. An external display cannot; the system handles those keys itself.
    var canSetBrightness: Bool { get }
    func read() -> Double?
    func write(_ fraction: Double) -> Bool
}

/// DisplayServices, a private framework (see ARCHITECTURE, next to MediaRemote): loaded when first asked, and any missing symbol or failed
/// call means the keys are left to the system.
@MainActor
final class DisplayServicesBrightness: DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    private struct Symbols {
        let get: GetBrightness
        let set: SetBrightness
        let canChange: CanChange
    }

    private lazy var symbols: Symbols? = {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
            let get = dlsym(handle, "DisplayServicesGetBrightness"),
            let set = dlsym(handle, "DisplayServicesSetBrightness"),
            let can = dlsym(handle, "DisplayServicesCanChangeBrightness")
        else { return nil }
        return Symbols(
            get: unsafeBitCast(get, to: GetBrightness.self), set: unsafeBitCast(set, to: SetBrightness.self),
            canChange: unsafeBitCast(can, to: CanChange.self))
    }()

    private var display: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    var canSetBrightness: Bool {
        guard let symbols, let display else { return false }
        return symbols.canChange(display)
    }

    func read() -> Double? {
        guard let symbols, let display else { return nil }
        var value: Float = 0
        return symbols.get(display, &value) == 0 ? Double(value) : nil
    }

    func write(_ fraction: Double) -> Bool {
        guard let symbols, let display else { return false }
        return symbols.set(display, Float(min(max(fraction, 0), 1))) == 0
    }
}

// MARK: The tap

/// Something that hears the volume keys and decides, for each press, whether it is consumed.
@MainActor
protocol MediaKeyTapping: AnyObject {
    /// Starts hearing the keys. False when the system refuses (no Accessibility access). `onDisabled` runs when the system turns the tap off
    /// for good, which is what revoking the permission does.
    func start(
        handler: @escaping @MainActor (MediaKeyEvent) -> KeyDisposition, onDisabled: @escaping @MainActor () -> Void
    ) -> Bool
    func stop()
}

/// An event tap on the system-defined events (`NX_SYSDEFINED`), which is where the media keys arrive. The same kind of tap Clean Keys holds, and
/// like it, turned back on when macOS switches it off for being slow. It exists only between `start` and `stop`.
@MainActor
final class SystemMediaKeyTap: MediaKeyTapping {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: (@MainActor (MediaKeyEvent) -> KeyDisposition)?
    private var onDisabled: (@MainActor () -> Void)?

    func start(
        handler: @escaping @MainActor (MediaKeyEvent) -> KeyDisposition, onDisabled: @escaping @MainActor () -> Void
    ) -> Bool {
        guard tap == nil else { return true }
        self.handler = handler
        self.onDisabled = onDisabled
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<SystemMediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            // The answer is only whether to consume it, which is all that crosses into the main actor's code.
            let consume = MainActor.assumeIsolated { owner.receive(type: type, event: event) }
            return consume ? nil : Unmanaged.passUnretained(event)
        }
        let mask = CGEventMask(1) << CGEventMask(Self.systemDefined.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
                callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            self.handler = nil
            self.onDisabled = nil
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
        onDisabled = nil
    }

    private static let systemDefined = CGEventType(rawValue: 14)!

    /// Whether the event is consumed.
    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout:
            // Too slow for the system's liking: on again, and keep going.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .tapDisabledByUserInput:
            // The permission was taken away, or the tap was switched off on purpose: it is not coming back.
            onDisabled?()
            return false
        default:
            guard let key = Self.mediaKey(from: event) else { return false }
            return handler?(key) == .consume
        }
    }

    /// A volume key press, or nil for any other system-defined event. `data1` holds the key in its high half and its state in the low: the
    /// key is down when bits 8 to 15 are 0xA, and bit 0 marks a repeat.
    nonisolated static func mediaKey(from event: CGEvent) -> MediaKeyEvent? {
        guard let system = NSEvent(cgEvent: event), system.type == .systemDefined, system.subtype.rawValue == 8 else {
            return nil
        }
        let data = system.data1
        guard let key = MediaKey(rawValue: (data & 0xFFFF_0000) >> 16) else { return nil }
        let flags = data & 0x0000_FFFF
        let quarter = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        return MediaKeyEvent(
            key: key, isDown: ((flags & 0xFF00) >> 8) == 0xA, isRepeat: flags & 0x1 != 0, isQuarterStep: quarter)
    }
}

// MARK: The controller

/// Takes the volume and brightness keys while it is on, sets the level, and says what to show. It exists only while the setting is on, and holds an event tap
/// only then: no timers, nothing polls.
@MainActor
@Observable
final class LevelHUDController {
    enum Outcome: Equatable {
        case started
        /// Accessibility isn't allowed, so there is no tap to make.
        case needsAccess
        case failed
    }

    private(set) var isActive = false

    /// A level changed and the HUD should show it.
    @ObservationIgnored var onShow: ((LevelReading) -> Void)?
    /// The system turned the tap off (the permission was taken away): the controller has stopped.
    @ObservationIgnored var onLostAccess: (() -> Void)?
    /// Whether the island can show the HUD now. When it can't (it is open, or an alert that needs the person is up), the key goes to the
    /// system and its own HUD, so a press is never unanswered.
    @ObservationIgnored var canShow: () -> Bool = { true }
    /// Clean Keys holds its own tap, and must have the keys to itself.
    @ObservationIgnored var isSuspended: () -> Bool = { false }
    @ObservationIgnored var hasAccess: () -> Bool = { AXIsProcessTrusted() }

    @ObservationIgnored private let tap: MediaKeyTapping
    @ObservationIgnored private let volume: SystemVolume
    @ObservationIgnored private let brightness: DisplayBrightness

    init(tap: MediaKeyTapping? = nil, volume: SystemVolume? = nil, brightness: DisplayBrightness? = nil) {
        self.tap = tap ?? SystemMediaKeyTap()
        self.volume = volume ?? CoreAudioVolume()
        self.brightness = brightness ?? DisplayServicesBrightness()
    }

    /// Makes the tap. Safe to call again.
    @discardableResult
    func start() -> Outcome {
        guard !isActive else { return .started }
        guard hasAccess() else { return .needsAccess }
        let made = tap.start(
            handler: { [weak self] event in self?.handle(event) ?? .passThrough },
            onDisabled: { [weak self] in
                guard let self, isActive else { return }
                stop()
                onLostAccess?()
            })
        guard made else { return .failed }
        isActive = true
        return .started
    }

    /// Removes the tap at once, and the system's HUD is back.
    func stop() {
        guard isActive else { return }
        tap.stop()
        isActive = false
    }

    /// One key press. A key this does not take is left for the system, including every key while the device can't be set.
    func handle(_ event: MediaKeyEvent) -> KeyDisposition {
        guard isActive, !isSuspended(), canShow() else { return .passThrough }
        switch event.key {
        case .volumeUp, .volumeDown, .mute:
            guard volume.canSetVolume, let current = volume.read() else { return .passThrough }
            // A key up follows a key down that was taken: take it too, so nothing else sees half a press.
            guard event.isDown else { return .consume }
            let next = VolumeStep.apply(event.key, to: current, quarter: event.isQuarterStep)
            guard volume.write(next) else { return .passThrough }
            onShow?(.volume(next))
            return .consume
        case .brightnessUp, .brightnessDown:
            guard brightness.canSetBrightness, let current = brightness.read() else { return .passThrough }
            guard event.isDown else { return .consume }
            let next = LevelStep.step(current, up: event.key == .brightnessUp, quarter: event.isQuarterStep)
            guard brightness.write(next) else { return .passThrough }
            onShow?(.brightness(next))
            return .consume
        }
    }
}
