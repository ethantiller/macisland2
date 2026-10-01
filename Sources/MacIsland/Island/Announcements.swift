import SwiftUI

/// Interruptions that arrive on their own, each of which can be turned off in Settings. What you just did yourself
/// (Copied, Zipped, Saved, a timer finishing) is feedback and always shows, so it is not here.
enum AmbientEvent: String, CaseIterable, Identifiable {
    case charging, fullCharge, lowBattery
    case headphones, drive, hotspot, unlocked
    case meeting, reminderDue, rainSoon
    case download, lowDisk
    case agentDone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .charging: "Charging"
        case .fullCharge: "Full Charge"
        case .lowBattery: "Low Battery"
        case .headphones: "Headphones"
        case .drive: "Drives"
        case .hotspot: "Personal Hotspot"
        case .unlocked: "Unlocked"
        case .meeting: "Meetings"
        case .reminderDue: "Due Reminders"
        case .rainSoon: "Rain Soon"
        case .download: "Downloads"
        case .lowDisk: "Low Disk Space"
        case .agentDone: "Task Finished"
        }
    }

    enum Group: String, CaseIterable, Identifiable {
        case power = "Power"
        case devices = "Devices"
        case day = "Your Day"
        case storage = "Storage"
        case agents = "AI Agents"

        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .charging, .fullCharge, .lowBattery: .power
        case .headphones, .drive, .hotspot, .unlocked: .devices
        case .meeting, .reminderDue, .rainSoon: .day
        case .download, .lowDisk: .storage
        case .agentDone: .agents
        }
    }
}

/// What an ambient event shows: a banner, or a short alert beside the notch.
enum Announcement {
    case banner(IslandBanner)
    case alert(IslandAlert)
}

/// The banners and alerts of ambient events, built in one place so the Settings preview draws exactly what the
/// island does.
@MainActor
enum Announcements {
    /// A task an agent worked on has finished: "Done 4:12", in green, with the module's sparkles.
    static func agentDone(duration: TimeInterval) -> IslandAlert {
        IslandAlert(
            systemImage: "sparkles", tint: Theme.Tint.positive, text: "Done " + formatTime(duration), opensTab: .agents)
    }

    static func charging(percent: Int) -> IslandAlert {
        IslandAlert(systemImage: "bolt.fill", tint: Theme.Tint.positive, text: "\(percent)%", isCharging: true)
    }

    static func fullCharge(percent: Int) -> IslandAlert {
        IslandAlert(systemImage: "battery.100percent", tint: Theme.Tint.positive, text: "\(percent)%")
    }

    /// A centered alert, with nothing to press: turning on Low Power Mode needs an administrator's password every time, so it is
    /// not offered here.
    static func lowBattery(percent: Int) -> (banner: IslandBanner, followUp: IslandAlert) {
        (
            IslandBanner(
                systemImage: "battery.25percent",
                tint: Theme.Tint.attention,
                title: "Low Battery",
                detail: "\(percent)% remaining"
            ),
            IslandAlert(
                systemImage: "battery.25percent", tint: Theme.Tint.attention, text: "\(percent)%",
                staysUntilSeen: true, opensTab: .tools)
        )
    }

    static func headphones(_ accessory: AudioAccessory) -> IslandBanner {
        IslandBanner(
            systemImage: accessory.systemImage,
            tint: Theme.Tint.neutral,
            title: accessory.name,
            detail: accessory.batterySummary ?? "Connected",
            ringTint: accessory.isLow ? Theme.Tint.attention : Theme.Tint.positive
        )
    }

    static func drive(_ volume: VolumeMonitor.Volume, eject: @escaping @MainActor () -> Void) -> IslandBanner {
        IslandBanner(
            systemImage: "externaldrive.fill",
            tint: Theme.Tint.neutral,
            title: volume.name,
            detail: volume.detail,
            actions: [.init(title: "Eject", perform: eject)]
        )
    }

    /// The volume HUD: the speaker for the level, in white, and in red only when muted or at zero.
    static func volume(_ level: VolumeLevel) -> IslandAlert {
        var alert = IslandAlert(
            systemImage: level.symbol, tint: level.isSilent ? Theme.Tint.attention : Theme.Tint.neutral,
            text: "\(level.percent)%", tintsText: level.isSilent)
        alert.volume = level
        return alert
    }

    static var hotspot: IslandAlert {
        IslandAlert(systemImage: "personalhotspot", tint: Theme.Tint.positive, text: "Hotspot")
    }

    static var unlocked: IslandAlert {
        IslandAlert(systemImage: "touchid", tint: Theme.Tint.positive, text: "Unlocked")
    }

    static var downloadSaved: IslandAlert {
        IslandAlert(systemImage: "arrow.down.circle.fill", tint: Theme.Tint.positive, text: "Saved")
    }

    static func rainSoon(start: Date) -> IslandBanner {
        IslandBanner(
            systemImage: "cloud.rain.fill",
            tint: Theme.Tint.neutral,
            title: "Rain Soon",
            detail: "Starts around \(start.formatted(date: .omitted, time: .shortened))"
        )
    }

    static func lowDisk(free: Int64) -> (banner: IslandBanner, followUp: IslandAlert) {
        (
            IslandBanner(
                systemImage: "internaldrive.fill",
                tint: Theme.Tint.attention,
                title: "Low Disk Space",
                detail: DiskSpace.description(free: free),
                actions: [.init(title: "Open Storage") { DiskSpace.openStorageSettings() }]
            ),
            IslandAlert(
                systemImage: "internaldrive.fill", tint: Theme.Tint.attention,
                text: ByteCountFormatter.string(fromByteCount: free, countStyle: .file), staysUntilSeen: true)
        )
    }

    /// What an event looks like, for the Settings preview. Nothing here acts on the Mac.
    static func sample(for event: AmbientEvent, agenda: AgendaMonitor) -> Announcement {
        switch event {
        case .charging: .alert(charging(percent: 64))
        case .fullCharge: .alert(fullCharge(percent: 100))
        case .lowBattery: .banner(lowBattery(percent: 18).banner)
        case .headphones:
            .banner(headphones(AudioAccessory(name: "AirPods Pro", left: 82, right: 80, caseLevel: 64, main: nil)))
        case .drive:
            .banner(
                drive(.init(url: URL(fileURLWithPath: "/Volumes/Backup"), name: "Backup", capacity: 1_000_000_000_000))
                {})
        case .hotspot: .alert(hotspot)
        case .unlocked: .alert(unlocked)
        case .meeting:
            .banner(AgendaAction.announcement(for: PreviewSamples.nextEvent(), agenda: agenda) {})
        case .reminderDue:
            .banner(
                AgendaAction.announcement(
                    for: AgendaItem(
                        id: "preview-reminder", kind: .reminder, title: "Call the bank", date: Date(),
                        reminderID: nil, joinURL: nil), agenda: agenda
                ) {})
        case .rainSoon: .banner(rainSoon(start: Date().addingTimeInterval(20 * 60)))
        case .download: .alert(downloadSaved)
        case .lowDisk: .banner(lowDisk(free: 4_000_000_000).banner)
        case .agentDone: .alert(agentDone(duration: 252))
        }
    }
}
