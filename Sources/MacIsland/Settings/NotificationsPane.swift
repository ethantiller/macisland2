import SwiftUI

/// Which interruptions reach you. Each one can be turned off; selecting one shows its real banner in the preview.
struct NotificationsPane: View {
    let settings: AppSettings
    let preview: IslandPreviewModel?

    var body: some View {
        Form {
            Section {
                Toggle("Quiet in Focus", isOn: Bindable(settings).quietDuringFocus)
                    .tourAnchor(.quietInFocus)
            } header: {
                Text("Interruptions").id(SettingsAnchor.interruptions)
            } footer: {
                Text(
                    "While a Focus is on, banners and alerts wait. Anything that needs you still shows. What you just did yourself (Copied, Zipped, Saved, a timer finishing) always shows."
                )
            }
            Section {
                Toggle("Replace the Volume HUD", isOn: Bindable(settings).replacesVolumeHUD)
                    .onChange(of: settings.replacesVolumeHUD) {
                        preview?.show(PreviewContext(presentation: .banner, showsVolume: true))
                    }
            } header: {
                Text("Volume").id(SettingsAnchor.volumeHUD)
            } footer: {
                Text(
                    "Shows the volume in the island instead of the system\u{2019}s square. MacIsland takes the volume and mute keys, which needs Accessibility access: turning this on asks, and stays off until it is allowed. Turning it off, or taking the access away, gives the keys back at once. Only while the island is folded; open, or with an alert that needs you, the system shows its own. An output that has no volume (some HDMI and DisplayPort displays) is left to the system."
                )
            }
            ForEach(AmbientEvent.Group.allCases) { group in
                Section {
                    ForEach(AmbientEvent.allCases.filter { $0.group == group }) { event in
                        row(event)
                    }
                    if group == .power {
                        SettingsDropdown(
                            title: "Full Charge Alert", selection: Bindable(settings).fullChargeLevel,
                            options: DropdownOption.all(Array(stride(from: 80, through: 100, by: 5))) { "\($0)%" })
                    }
                } header: {
                    Text(group.rawValue).id(Self.anchor(for: group))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// What has to be on for an event to ever happen.
    /// Where search scrolls to for a group of events.
    static func anchor(for group: AmbientEvent.Group) -> String {
        switch group {
        case .power: SettingsAnchor.power
        case .devices: SettingsAnchor.devices
        case .day: SettingsAnchor.yourDay
        case .storage: SettingsAnchor.storage
        }
    }

    private func requirement(_ event: AmbientEvent) -> String? {
        switch event {
        case .meeting: settings.showsCalendar ? nil : "Turn on Calendar Events in Home."
        case .reminderDue: settings.showsReminders ? nil : "Turn on Due Reminders in Home."
        case .rainSoon: settings.weatherCity.isEmpty ? "Set a city in Home." : nil
        default: nil
        }
    }

    private func row(_ event: AmbientEvent) -> some View {
        let note = requirement(event)
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(
                event.title,
                isOn: Binding(
                    get: { !settings.isMuted(event) },
                    set: { settings.setMuted(event, !$0) }
                )
            )
            .disabled(note != nil)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { preview?.show(PreviewContext(presentation: .banner, event: event)) }
        )
    }
}
