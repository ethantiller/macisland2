import AppKit
import SwiftUI

/// What Home and the idle peek show: the next meeting or reminder, or a quiet
/// "Nothing Scheduled". Errors say how to fix them and take you there.
struct IdleView: View {
    let agenda: AgendaMonitor

    var body: some View {
        if let item = agenda.next {
            // Re-evaluated every 30s so "in 5 min" keeps counting down.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                row(for: item, now: context.date)
            }
        } else if agenda.isDenied {
            HStack(spacing: 12) {
                Label("Calendar Access Is Off", systemImage: "calendar.badge.exclamationmark")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                ChipButton(title: "Allow Access", action: AgendaMonitor.openPrivacySettings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Label("Nothing Scheduled", systemImage: "calendar")
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(for item: AgendaItem, now: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .event ? "calendar" : "checklist")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.Palette.primary)
                .frame(width: Theme.Metrics.artwork)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.primary)
                Text(AgendaRules.timeText(for: item, now: now))
                    .font(Theme.Typography.body.monospacedDigit())
                    .foregroundStyle(Theme.Palette.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if let action = AgendaAction(item: item, agenda: agenda) {
                ChipButton(title: action.title, action: action.perform)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The one action an agenda item offers: Join a call, or mark a reminder Done.
struct AgendaAction {
    let title: String
    let perform: () -> Void

    @MainActor
    init?(item: AgendaItem, agenda: AgendaMonitor) {
        if let url = item.joinURL {
            title = "Join"
            perform = { MeetingLink.join(url) }
        } else if item.kind == .reminder {
            title = "Done"
            perform = { agenda.complete(item) }
        } else {
            return nil
        }
    }
}

extension AgendaAction {
    /// The banner five minutes before a meeting or when a reminder is due. A meeting with a call link gets **Join** and,
    /// second, **Check Camera**, so there is a look at yourself before the call.
    @MainActor
    static func announcement(
        for item: AgendaItem, agenda: AgendaMonitor, now: Date = Date(), checkCamera: @escaping @MainActor () -> Void
    ) -> IslandBanner {
        let isEvent = item.kind == .event
        var actions =
            AgendaAction(item: item, agenda: agenda).map { [IslandBanner.Action(title: $0.title, perform: $0.perform)] }
            ?? []
        if isEvent, item.joinURL != nil {
            actions.append(.init(title: "Check Camera", perform: checkCamera))
        }
        return IslandBanner(
            systemImage: isEvent ? "calendar" : "checklist",
            tint: Theme.Tint.neutral,
            title: item.title,
            detail: isEvent ? AgendaRules.timeText(for: item, now: now) : "Due now",
            actions: actions
        )
    }
}
