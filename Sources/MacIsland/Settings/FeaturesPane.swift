import AppKit
import SwiftUI

/// Features: a switch for each part of MacIsland. Off, a feature doesn't show and doesn't run, and its settings are kept. Choosing a row
/// shows where the feature lands on the island.
struct FeaturesPane: View {
    let settings: AppSettings
    let features: IslandFeatures
    let preview: IslandPreviewModel?

    /// What turning a feature off stopped, under its row until the pane is left.
    @State private var notices: [Feature: String] = [:]
    /// Optional permissions the person said Not Now to, until the pane is left.
    @State private var dismissed: Set<OptionalAccess> = []

    private static let ownChoice = "own"

    var body: some View {
        Form {
            Section {
                SettingsDropdown(title: "Start From", selection: presetBinding, options: presetOptions)
                    .tourAnchor(.featureList)
            } header: {
                Text("Presets").id(SettingsAnchor.featurePresets)
            } footer: {
                let count = settings.featureCount
                Text("\(count.on) of \(count.of) on.")
            }
            ForEach(Feature.Group.allCases, id: \.self) { group in
                let rows = Feature.allCases.filter { $0.group == group && $0.isBuilt }
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { row($0) }
                    } header: {
                        Text(group.rawValue)
                    } footer: {
                        if group == Feature.Group.allCases.last {
                            Text(
                                "Off means it doesn\u{2019}t show and doesn\u{2019}t run. Its settings are kept for when you turn it back on. New features start off."
                            )
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Presets

    private var presetOptions: [DropdownOption<String>] {
        var options = FeaturePreset.allCases.map { DropdownOption($0.rawValue, $0.title) }
        if settings.matchingPreset() == nil { options.append(DropdownOption(Self.ownChoice, "Your Own")) }
        return options
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: { settings.matchingPreset()?.rawValue ?? Self.ownChoice },
            set: { raw in
                guard let preset = FeaturePreset(rawValue: raw), preset != settings.matchingPreset() else { return }
                if Self.confirm(preset) {
                    notices = [:]
                    settings.apply(preset)
                }
            })
    }

    private static func confirm(_ preset: FeaturePreset) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Use \(preset.title)?"
        alert.informativeText = preset.confirmation
        alert.addButton(withTitle: "Use \(preset.title)")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Rows

    private func row(_ feature: Feature) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(
                feature.title,
                isOn: Binding(
                    get: { settings.isOn(feature) },
                    set: { on in
                        // Said before it happens, while what is running can still be read.
                        notices[feature] = on ? nil : FeatureNotice.whatStops(feature, features: features)
                        settings.setOn(feature, on)
                        show(feature)
                    }))
            Text(feature.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(feature.cost.words)
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let note = notices[feature] {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            accessLines(feature)
            notificationLines(feature)
        }
        .id(SettingsAnchor.feature(feature))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { show(feature) })
    }

    /// A feature that is on and needs a permission nobody has been asked for says why first, and asks only when Allow is pressed (a
    /// preset never asks; it shows this line). A permission that was refused offers System Settings.
    @ViewBuilder private func accessLines(_ feature: Feature) -> some View {
        if settings.isOn(feature), let model = AccessCenter.model {
            ForEach(feature.optionalAccess) { access in
                switch model.state(of: access) {
                case .notAsked where !dismissed.contains(access):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(access.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            FieldButton(title: "Allow") { Task { await model.allow(access) } }
                            FieldButton(title: "Not Now") { dismissed.insert(access) }
                        }
                    }
                case .denied:
                    HStack(spacing: 8) {
                        Text("\(access.title) is off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let url = access.settingsURL {
                            FieldButton(title: "Open System Settings") { NSWorkspace.shared.open(url) }
                        }
                    }
                default:
                    EmptyView()
                }
            }
        }
    }

    /// Notifications is read through Accessibility, one of the ten the guide asks for: when it is off, or the version of macOS isn't one
    /// this knows, the row says why.
    @ViewBuilder private func notificationLines(_ feature: Feature) -> some View {
        if feature == .notifications, settings.isOn(feature), let problem = features.notifications.problem {
            VStack(alignment: .leading, spacing: 6) {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if features.notifications.reader.status == .needsAccess {
                    HStack(spacing: 8) {
                        if let url = AccessKind.accessibility.settingsURL {
                            FieldButton(title: "Open System Settings") { NSWorkspace.shared.open(url) }
                        }
                        FieldButton(title: "Check Again") { features.notifications.start() }
                    }
                }
            }
        }
    }

    private func show(_ feature: Feature) {
        if let preview, let context = feature.previewContext(from: preview.context) { preview.show(context) }
    }
}
