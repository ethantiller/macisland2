import AppKit

/// Announces external drives as they mount, so they can be ejected from the island.
@MainActor
final class VolumeMonitor {
    struct Volume: Sendable {
        let url: URL
        let name: String
        let capacity: Int64?

        var detail: String {
            capacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Mounted"
        }
    }

    var onMount: ((Volume) -> Void)?

    private var observer: Any?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated {
                if let volume = Self.volume(at: url) { self?.onMount?(volume) }
            }
        }
    }

    /// Only local, browsable drives that can be ejected: not the startup disk, network shares, or hidden volumes.
    nonisolated static func isEjectableDrive(isLocal: Bool, isBrowsable: Bool, isInternal: Bool, isEjectable: Bool)
        -> Bool
    {
        isLocal && isBrowsable && !isInternal && isEjectable
    }

    private static func volume(at url: URL) -> Volume? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsInternalKey,
            .volumeIsEjectableKey, .volumeTotalCapacityKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
            isEjectableDrive(
                isLocal: values.volumeIsLocal ?? false,
                isBrowsable: values.volumeIsBrowsable ?? false,
                isInternal: values.volumeIsInternal ?? true,
                isEjectable: values.volumeIsEjectable ?? false
            )
        else { return nil }
        return Volume(
            url: url,
            name: values.volumeName ?? url.lastPathComponent,
            capacity: values.volumeTotalCapacity.map(Int64.init)
        )
    }

    /// `nil` when it ejected, or the reason it didn't.
    nonisolated static func eject(_ volume: Volume) -> String? {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
