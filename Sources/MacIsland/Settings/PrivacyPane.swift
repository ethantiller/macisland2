import SwiftUI

/// Everything that leaves this Mac or runs on it, and what MacIsland may access. All of it is readable here, and
/// the ones that can be turned off or removed can be, from here.
struct PrivacyPane: View {
    let settings: AppSettings

    @State private var access: [PrivacyAccess] = []

    private var webWidgets: [CustomWidget] { settings.customWidgets.filter { $0.webHost != nil } }
    private var shortcutWidgets: [CustomWidget] {
        settings.customWidgets.filter { if case .shortcut = $0.source { true } else { false } }
    }
    private var commandWidgets: [CustomWidget] { settings.customWidgets.filter(\.isCommand) }

    var body: some View {
        Form {
            Section {
                if !settings.weatherCity.isEmpty {
                    row(
                        "Open-Meteo", "Your weather city: \u{201C}\(settings.weatherCity)\u{201D}. Nothing else.",
                        action: "Turn Off"
                    ) { settings.weatherCity = "" }
                }
                if settings.showsLyrics {
                    row(
                        "lrclib.net", "The playing track\u{2019}s name, artist, album, and length, for synced lyrics.",
                        action: "Turn Off"
                    ) { settings.showsLyrics = false }
                }
                ForEach(webWidgets) { widget in
                    row(
                        widget.webHost ?? "Web", "The address of \u{201C}\(widget.title)\u{201D}, including its query.",
                        action: "Remove"
                    ) { settings.removeCustomWidget(widget.id) }
                }
            } header: {
                Text("What Leaves This Mac").id(SettingsAnchor.leavesThisMac)
            } footer: {
                Text("Nothing else is sent anywhere. There is no account, no analytics, and no server of ours.")
            }

            Section {
                row("Now Playing adapter", "/usr/bin/perl runs a bundled script that reads what is playing.")
                if settings.isOn(.agents) {
                    row("AI Agents", "Reads the Claude Code and Codex logs in your home folder. Nothing is sent.")
                }
                ForEach(shortcutWidgets) { widget in
                    if case .shortcut(let name, _) = widget.source {
                        row(
                            "Shortcut: \(name)", "Run by \u{201C}\(widget.title)\u{201D}, with no input.",
                            action: "Remove"
                        ) { settings.removeCustomWidget(widget.id) }
                    }
                }
                ForEach(commandWidgets) { widget in
                    if case .command(let path) = widget.source {
                        row(
                            (path as NSString).abbreviatingWithTildeInPath,
                            "Run by \u{201C}\(widget.title)\u{201D} as you. It stays on this Mac.", action: "Remove"
                        ) { settings.removeCustomWidget(widget.id) }
                    }
                }
            } header: {
                Text("Things MacIsland Runs").id(SettingsAnchor.runs)
            } footer: {
                Text(
                    "Custom widgets run only while Home is showing. Command widgets are never exported, imported, or started by a link."
                )
            }

            Section {
                ForEach(access) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.state.rawValue)
                            .foregroundStyle(.secondary)
                        // Nothing has asked yet: this is where to ask, at a moment of your own choosing. Speech Recognition is asked
                        // with the Microphone.
                        if item.state == .notAsked,
                            let kind = AccessKind(rawValue: item.id == "speech" ? AccessKind.microphone.rawValue : item.id)
                        {
                            Button("Grant") {
                                Task {
                                    await AccessCenter.model?.allow(kind)
                                    access = PrivacyAccess.current()
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                        Button("Open System Settings") { NSWorkspace.shared.open(item.settingsURL) }
                            .buttonStyle(.borderless)
                    }
                    .accessibilityElement(children: .combine)
                    .tourAnchor(item.id == access.first?.id ? .accessList : nil)
                }
            } header: {
                Text("Access").id(SettingsAnchor.access)
            } footer: {
                Text(
                    "Read without asking. Grant asks for one now; nothing is asked at launch, only here, in the welcome guide, or when you use what needs it."
                )
            }
            optionalAccessSection
        }
        .formStyle(.grouped)
        .onAppear { access = PrivacyAccess.current() }
    }

    /// Permissions only an optional feature needs. Listed once such a feature exists in this build; never asked at launch.
    @ViewBuilder private var optionalAccessSection: some View {
        let listed = OptionalAccess.allCases.filter { $0.feature.isBuilt }
        if !listed.isEmpty {
            Section {
                ForEach(listed) { item in
                    let state = AccessCenter.model?.state(of: item) ?? .notAsked
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.usage(settings: settings))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(state.words)
                            .foregroundStyle(.secondary)
                        if state == .notAsked, settings.isOn(item.feature) {
                            Button("Grant") { Task { await AccessCenter.model?.allow(item) } }
                                .buttonStyle(.borderless)
                        }
                        if let url = item.settingsURL {
                            Button("Open System Settings") { NSWorkspace.shared.open(url) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Optional Access").id(SettingsAnchor.optionalAccess)
            } footer: {
                Text(
                    "Only a feature you turn on uses these, and macOS can't say whether they are on, so this shows what MacIsland has seen. They are asked in Features, never at launch."
                )
            }
        }
    }

    private func row(_ title: String, _ detail: String, action: String? = nil, perform: (() -> Void)? = nil)
        -> some View
    {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let action, let perform {
                Button(action, role: .destructive, action: perform)
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
