import CoreAudio
import Foundation

/// Physical audio output devices and which one is the system default.
@MainActor
@Observable
final class AudioOutputs {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        let transportType: UInt32
        /// The device's persistent identifier, which the Mixer stores to send an app to it.
        var uid: String?

        var isBluetooth: Bool {
            transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
        }

        var systemImage: String {
            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn: "laptopcomputer"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
            case kAudioDeviceTransportTypeAirPlay: "airplayaudio"
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: "tv"
            default: "hifispeaker"
            }
        }
    }

    private(set) var devices: [Device] = []
    private(set) var defaultDeviceID = AudioDeviceID(kAudioObjectUnknown)

    var currentDevice: Device? {
        Self.currentDevice(in: devices, defaultDeviceID: defaultDeviceID)
    }

    var otherDevices: [Device] {
        Self.otherDevices(in: devices, defaultDeviceID: defaultDeviceID)
    }

    static func currentDevice(in devices: [Device], defaultDeviceID: AudioDeviceID) -> Device? {
        devices.first { $0.id == defaultDeviceID }
    }

    static func otherDevices(in devices: [Device], defaultDeviceID: AudioDeviceID) -> [Device] {
        devices.filter { $0.id != defaultDeviceID }
    }

    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?
    /// The devices or the default changed.
    @ObservationIgnored var onChange: (() -> Void)?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    init(devices: [Device], defaultDeviceID: AudioDeviceID) {
        self.devices = devices
        self.defaultDeviceID = defaultDeviceID
    }

    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.listener = listener
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, listener)
        }
        refresh()
    }

    func select(_ device: Device) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectSetPropertyData(Self.systemObject, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        refresh()
    }

    private func refresh() {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(Self.systemObject, &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &ids) == noErr else { return }

        devices = ids.compactMap { id in
            let transport = Self.transportType(of: id)
            guard Self.hasOutput(id),
                transport != kAudioDeviceTransportTypeVirtual,
                transport != kAudioDeviceTransportTypeAggregate,
                let name = Self.name(of: id)
            else { return nil }
            return Device(id: id, name: name, transportType: transport, uid: CoreAudioTapper.deviceUID(id))
        }

        var defaultID = AudioDeviceID(kAudioObjectUnknown)
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectGetPropertyData(Self.systemObject, &defaultAddress, 0, nil, &defaultSize, &defaultID) == noErr {
            defaultDeviceID = defaultID
        }
        onChange?()
    }

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func hasOutput(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
