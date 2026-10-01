import SwiftUI

/// The Home module, a dashboard of widgets in rows (`HomeGrid`). By default: today and what's next beside
/// what's playing, then the everyday tools beside the timers and the Shelf. Each piece takes the useful part
/// of another tab. The date opens a month calendar, which replaces the grid.
struct HomeView: View {
    let viewModel: IslandViewModel

    @State private var monthOffset = 0
    /// The events in the month shown, by day of the month. Read when the month appears and when it changes.
    @State private var eventDays: [Int: [AgendaItem]] = [:]

    private var isCalendarOpen: Bool { viewModel.calendarExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCalendarOpen {
                calendarHeader
                MonthGridView(
                    month: shownMonth, eventDays: Set(eventDays.keys), selectedDay: viewModel.calendarSelectedDay,
                    onSelect: { day in viewModel.calendarSelectedDay = viewModel.calendarSelectedDay == day ? nil : day }
                )
                .transition(.opacity)
                .task(id: monthOffset) { await loadEvents() }
            } else {
                HomeGrid(layout: viewModel.homeLayout, viewModel: viewModel)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onDisappear { monthOffset = 0 }
    }

    private func loadEvents() async {
        viewModel.calendarSelectedDay = nil
        guard viewModel.settings.isOn(.calendar),
            let interval = Calendar.current.dateInterval(of: .month, for: shownMonth)
        else {
            eventDays = [:]
            return
        }
        eventDays = await viewModel.agenda.eventDays(in: interval)
    }

    /// The month's name, or the chosen day's first event and how many more.
    private var headerTitle: String {
        guard let day = viewModel.calendarSelectedDay, let items = eventDays[day],
            let date = Calendar.current.date(
                bySetting: .day, value: day, of: Calendar.current.dateInterval(of: .month, for: shownMonth)?.start ?? shownMonth)
        else { return shownMonth.formatted(.dateTime.month(.wide).year()) }
        return AgendaRules.dayLine(for: date, items: items)
    }

    private var shownMonth: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var calendarHeader: some View {
        HStack(spacing: 4) {
            Button {
                // A chosen day goes back to the month first; then the calendar closes.
                if viewModel.calendarSelectedDay != nil {
                    viewModel.calendarSelectedDay = nil
                } else {
                    monthOffset = 0
                    viewModel.setCalendarExpanded(false)
                }
            } label: {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(Theme.Typography.title)
                        .lineLimit(1)
                        .foregroundStyle(Theme.Palette.primary)
                    Image(systemName: "chevron.up")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiary)
                }
                .frame(height: Theme.Metrics.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
            .accessibilityLabel("Hide Calendar")

            Spacer(minLength: 8)
            IconButton(systemName: "chevron.left", label: "Previous Month", size: 11) { monthOffset -= 1 }
            IconButton(systemName: "chevron.right", label: "Next Month", size: 11) { monthOffset += 1 }
        }
        .frame(height: Theme.Metrics.homeHeaderHeight)
    }
}
