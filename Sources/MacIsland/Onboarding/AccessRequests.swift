import EventKit
import Foundation
import Observation

/// What the first-run guide asks for up front: the permissions behind things that arrive on their own (meeting and due
/// banners, Up Next, the headphones banner), so there is no "first use" to ask at. The raw value is `PrivacyAccess.id`.
enum AccessKind: String, CaseIterable {
    case calendars, reminders, bluetooth
}

@MainActor
protocol AccessProviding: AnyObject {
    func state(of kind: AccessKind) -> PrivacyAccess.State
    /// Asks the system if it was never asked, and says whether access is now allowed.
    func request(_ kind: AccessKind) async -> Bool
}

/// The real Mac. States come from `PrivacyAccess.current()`; requests use the app's own paths.
@MainActor
final class LiveAccess: AccessProviding {
    private let agenda: AgendaMonitor
    private let bluetooth: BluetoothAccess

    init(agenda: AgendaMonitor, bluetooth: BluetoothAccess) {
        self.agenda = agenda
        self.bluetooth = bluetooth
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State {
        PrivacyAccess.current().first { $0.id == kind.rawValue }?.state ?? .notAsked
    }

    func request(_ kind: AccessKind) async -> Bool {
        switch kind {
        case .calendars: await agenda.requestAccess(to: .event)
        case .reminders: await agenda.requestAccess(to: .reminder)
        case .bluetooth: await bluetooth.request()
        }
    }
}

/// Where each permission stands for the guide, and what asking for one does.
@MainActor
@Observable
final class AccessModel {
    private(set) var states: [AccessKind: PrivacyAccess.State]
    /// The permission whose system prompt is showing.
    private(set) var asking: AccessKind?

    @ObservationIgnored private let provider: AccessProviding
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let onBluetoothAllowed: () -> Void

    init(provider: AccessProviding, settings: AppSettings, onBluetoothAllowed: @escaping () -> Void) {
        self.provider = provider
        self.settings = settings
        self.onBluetoothAllowed = onBluetoothAllowed
        states = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, provider.state(of: $0)) })
    }

    func state(of kind: AccessKind) -> PrivacyAccess.State { states[kind] ?? .notAsked }

    var allAllowed: Bool { AccessKind.allCases.allSatisfy { state(of: $0) == .allowed } }

    /// Reads every state again: after a system prompt closes, and when the person comes back from System Settings.
    func refresh() {
        let fresh = Dictionary(uniqueKeysWithValues: AccessKind.allCases.map { ($0, provider.state(of: $0)) })
        if fresh != states { states = fresh }
    }

    /// Asks for one permission. A grant also turns on the feature it serves, so the permission and the choice are one step;
    /// a denial changes nothing (macOS answers no at once from then on, so a denied row offers System Settings instead).
    func allow(_ kind: AccessKind) async {
        guard asking == nil, state(of: kind) == .notAsked else { return }
        asking = kind
        let granted = await provider.request(kind)
        asking = nil
        if granted {
            switch kind {
            case .calendars: if !settings.showsCalendar { settings.showsCalendar = true }
            case .reminders: if !settings.showsReminders { settings.showsReminders = true }
            case .bluetooth: onBluetoothAllowed()
            }
        }
        refresh()
    }

    /// Every permission still never asked, in `AccessKind` order, one after another. Skip uses it.
    func requestAllPending() async {
        for kind in AccessKind.allCases where state(of: kind) == .notAsked { await allow(kind) }
    }
}
