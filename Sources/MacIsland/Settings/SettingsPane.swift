import SwiftUI

/// The Settings window's sidebar. There is no Appearance pane: what the island looks like is not a setting.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, features, tabs, home, shelf, media, clock, tools, notifications, privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .features: "Features"
        case .tabs: "Tabs"
        case .home: "Home"
        case .shelf: "Shelf"
        case .media: "Media"
        case .clock: "Clock"
        case .tools: "Tools"
        case .notifications: "Notifications"
        case .privacy: "Privacy"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .features: "switch.2"
        case .tabs: "rectangle.split.3x1"
        case .home: "house"
        case .shelf: "tray.full"
        case .media: "music.note"
        case .clock: "timer"
        case .tools: "square.grid.2x2"
        case .notifications: "bell"
        case .privacy: "hand.raised"
        }
    }

    /// What the preview shows while the pane is open, so it follows what is being edited. Nil hides the preview
    /// (Privacy has nothing of the island to show).
    var previewContext: PreviewContext? {
        switch self {
        case .general: PreviewContext(presentation: .compact)
        case .features: PreviewContext(presentation: .expanded, tab: .home)
        case .tabs: PreviewContext(presentation: .expanded, tab: .home)
        case .home: PreviewContext(presentation: .expanded, tab: .home)
        case .shelf: PreviewContext(presentation: .compact, tab: .shelf, fileDrag: true)
        case .media: PreviewContext(presentation: .compact)
        case .clock: PreviewContext(presentation: .expanded, tab: .clock, clockMode: .pomodoro)
        case .tools: PreviewContext(presentation: .expanded, tab: .tools)
        case .notifications: PreviewContext(presentation: .banner)
        case .privacy: nil
        }
    }
}
