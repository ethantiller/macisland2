import SwiftUI

/// The Reminders tab: add one, see what's open, check them off.
struct RemindersView: View {
    let viewModel: IslandViewModel

    @State private var draft = ""
    @FocusState private var isFocused: Bool
    @Environment(\.isFloatingWindow) private var isFloating

    private var agenda: AgendaMonitor { viewModel.agenda }

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            addField
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await agenda.showReminderList() }
        .onDisappear { agenda.hideReminderList() }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.tertiary)
                .accessibilityHidden(true)
            TextField("Add Reminder", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primary)
                .focused($isFocused)
                .onSubmit(submit)
                .accessibilityLabel("New Reminder")
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.hitTarget)
        .background(Theme.Palette.fill, in: Capsule())
        .onChange(of: isFocused) { _, focused in if focused, !isFloating { viewModel.hold(.textFocus) } }
    }

    @ViewBuilder
    private var content: some View {
        if agenda.remindersDenied {
            HStack(spacing: 12) {
                Label("Reminders Access Is Off", systemImage: "checklist")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                ChipButton(title: "Allow Access", action: AgendaMonitor.openRemindersSettings)
            }
        } else if agenda.reminderRows.isEmpty {
            Label("All Caught Up", systemImage: "checkmark.circle")
                .font(Theme.Typography.bodyEmphasized)
                .foregroundStyle(Theme.Palette.secondary)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(agenda.reminderRows) { row in
                        ReminderRowView(row: row) { agenda.complete(reminderID: row.id) }
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func submit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        draft = ""
        viewModel.addReminder(title)
    }
}

struct ReminderRowView: View {
    let row: ReminderRow
    /// The due text is left out where there is no room for it (Home's narrowest Reminders).
    var showsDue = true
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "circle", label: "Mark \(row.title) Done", size: 15, action: onDone)
            Text(row.title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if showsDue {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(row.dueText(now: context.date))
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }
}
