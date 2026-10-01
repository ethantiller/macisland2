import SwiftUI

/// The days of a month laid out in weeks, for the calendar that opens from Home's date.
enum MonthGrid {
    /// Always six weeks so the height doesn't change as months do. `nil` is a blank cell.
    static func weeks(containing date: Date, calendar: Calendar = .current) -> [[Int?]] {
        guard let month = calendar.dateInterval(of: .month, for: date),
            let days = calendar.range(of: .day, in: .month, for: date)
        else { return [] }
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: leading) + days.map { Optional($0) }
        cells += Array(repeating: nil, count: 42 - cells.count)
        return stride(from: 0, to: 42, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Single-letter weekday names, starting from the calendar's first weekday.
    static func weekdayInitials(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
}

/// One month, today filled white. The month can be moved with the arrows in Home's header.
struct MonthGridView: View {
    let month: Date
    /// 20 in the calendar that replaces Home; Today at 3 by 3 is taller, to fill its box.
    var rowHeight: CGFloat = 20
    /// The days of the month that have an event, which get a dot.
    var eventDays: Set<Int> = []
    /// The day chosen, if one is; clicking a day with events calls `onSelect`.
    var selectedDay: Int?
    var onSelect: ((Int) -> Void)?

    private let calendar = Calendar.current

    var body: some View {
        let weeks = MonthGrid.weeks(containing: month, calendar: calendar)
        let today =
            calendar.isDate(month, equalTo: Date(), toGranularity: .month)
            ? calendar.component(.day, from: Date()) : nil
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(MonthGrid.weekdayInitials(calendar: calendar).enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 16)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day, isToday: day != nil && day == today)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.formatted(.dateTime.month(.wide).year()))
    }

    @ViewBuilder
    private func cell(_ day: Int?, isToday: Bool) -> some View {
        let hasEvents = day.map(eventDays.contains) ?? false
        let isSelected = day != nil && day == selectedDay
        let base = dayNumber(day, isToday: isToday, hasEvents: hasEvents)
            .background(isSelected && !isToday ? Theme.Palette.fill : Theme.Palette.none, in: Circle())
            .frame(maxWidth: .infinity, minHeight: rowHeight)
            .accessibilityLabel(
                (day.map(String.init) ?? "") + (hasEvents ? ", has events" : ""))
            .accessibilityAddTraits(isToday ? .isSelected : [])
        if let day, hasEvents, let onSelect {
            Button { onSelect(day) } label: { base.contentShape(Rectangle()) }
                .buttonStyle(IslandButtonStyle())
        } else {
            base
        }
    }

    /// The number in its circle (filled for today), with a small dot under it when the day has an event.
    private func dayNumber(_ day: Int?, isToday: Bool, hasEvents: Bool) -> some View {
        Text(day.map(String.init) ?? "")
            .font(Theme.Typography.numeral)
            .foregroundStyle(isToday ? Theme.Palette.inverse : Theme.Palette.primary)
            .frame(width: 20, height: 20)
            .background(isToday ? Theme.Palette.primary : Theme.Palette.none, in: Circle())
            .overlay(alignment: .bottom) {
                if hasEvents {
                    Circle()
                        .fill(isToday ? Theme.Palette.inverse : Theme.Palette.secondary)
                        .frame(width: Theme.Metrics.monthEventDot, height: Theme.Metrics.monthEventDot)
                        .offset(y: 2)
                }
            }
    }
}
