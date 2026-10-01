import SwiftUI

/// The Mixer, in the Media tab: where the Audio Output and Volume button already puts the output chips. A row per app that is
/// playing or has been adjusted, each with a slider from 0 to 200%, the percent, and where it plays. The island never asks for the
/// permission: without it the panel says so and points to Settings.
struct MixerPanel: View {
    let viewModel: IslandViewModel
    /// Whether there is a player above to go back to (the chevron).
    let canHide: Bool

    private var mixer: AppMixer { viewModel.mixer }

    var body: some View {
        VStack(spacing: Theme.Metrics.playerSpacing) {
            HStack(spacing: 8) {
                OutputPicker(outputs: viewModel.outputs, bluetooth: viewModel.bluetooth)
                if canHide {
                    IconButton(systemName: "chevron.up", label: "Hide Mixer", size: 12) {
                        withAnimation(Theme.Motion.resize) { viewModel.showsMediaOutputs = false }
                    }
                }
            }
            .frame(height: Theme.Metrics.playerScrubber)
            content
        }
        .onAppear { viewModel.bluetooth.refresh() }
    }

    /// The line the panel says in place of the apps while the permission isn't there; nil when it is (or can't be checked).
    static func line(for access: OptionalAccessState) -> String? {
        switch access {
        case .notAsked: "The Mixer needs System Audio Recording."
        case .denied: "System Audio Recording is off."
        case .asked, .allowed: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mixer.access {
        case .notAsked:
            message(Self.line(for: .notAsked) ?? "", isProblem: false, action: "Open Settings") {
                // Where it is turned on and asked for: the Features pane.
                UserDefaults.standard.set(SettingsPane.features.rawValue, forKey: "settings.pane")
                SettingsWindowController.shared.show()
            }
        case .denied:
            message(Self.line(for: .denied) ?? "", isProblem: true, action: "Open Settings") {
                if let url = OptionalAccess.systemAudio.settingsURL { NSWorkspace.shared.open(url) }
            }
        case .asked, .allowed:
            rows
        }
    }

    private func message(_ text: String, isProblem: Bool, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if isProblem {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Tint.attention)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(isProblem ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.secondary))
                .lineLimit(1)
            Spacer(minLength: 0)
            ChipButton(title: action, action: perform)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.mixerRowHeight, alignment: .leading)
    }

    @ViewBuilder
    private var rows: some View {
        let rows = mixer.rows
        if rows.isEmpty {
            Text("Nothing is making sound.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.mixerRowHeight)
        } else if rows.count > Theme.Metrics.mixerMaxRows {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) { ForEach(rows) { MixerRowView(row: $0, mixer: mixer, outputs: viewModel.outputs) } }
            }
            .frame(height: CGFloat(Theme.Metrics.mixerMaxRows) * Theme.Metrics.mixerRowHeight)
        } else {
            VStack(spacing: 0) { ForEach(rows) { MixerRowView(row: $0, mixer: mixer, outputs: viewModel.outputs) } }
        }
    }
}

/// One app: its name, a slider, its percent (double-click for 100%), and the output it plays on.
private struct MixerRowView: View {
    let row: MixerRow
    let mixer: AppMixer
    let outputs: AudioOutputs

    private var level: Double { mixer.level(for: row.id) }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            if row.isNeverTapped {
                Text("Calls and music apps stay as they are")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                IslandSlider(
                    value: level / 2, label: "\(row.name) Volume",
                    valueDescription: "\(Int((level * 100).rounded())) percent",
                    onChange: { mixer.previewLevel(AppMixer.snapped($0 * 2), for: row.id) },
                    onCommit: { mixer.setLevel(AppMixer.snapped($0 * 2), for: row.id) })
                Text("\(Int((level * 100).rounded()))%")
                    .font(Theme.Typography.numeral)
                    .foregroundStyle(Theme.Palette.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .onTapGesture(count: 2) { mixer.setLevel(1, for: row.id) }
                    .help("Double-click for 100%")
                outputMenu
            }
        }
        .frame(height: Theme.Metrics.mixerRowHeight)
    }

    private var outputTitle: String {
        guard let uid = mixer.output(for: row.id) else { return "Default" }
        return outputs.devices.first { $0.uid == uid }?.name ?? "Default"
    }

    private var outputMenu: some View {
        Menu {
            Button("Default") { mixer.setOutput(nil, for: row.id) }
            ForEach(outputs.devices) { device in
                Button(device.name) { mixer.setOutput(device.uid, for: row.id) }
            }
        } label: {
            ChipButton(title: outputTitle, isSelected: mixer.output(for: row.id) != nil) {}
                .allowsHitTesting(false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(maxWidth: 130)
        .accessibilityLabel("Output for \(row.name)")
    }
}
