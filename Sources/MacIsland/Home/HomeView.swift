import SwiftUI

/// The Home module, a dashboard of widgets in rows (`HomeGrid`). By default: today and what's next beside
/// what's playing, then the everyday tools beside the timers and the Shelf. Each piece takes the useful part
/// of another tab. The date opens a month calendar, which replaces the grid.
struct HomeView: View {
    let viewModel: IslandViewModel

    @State private var monthOffset = 0

    private var isCalendarOpen: Bool { viewModel.calendarExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCalendarOpen {
                calendarHeader
                MonthGridView(month: shownMonth)
                    .transition(.opacity)
            } else {
                HomeGrid(layout: viewModel.homeLayout, viewModel: viewModel)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onDisappear { monthOffset = 0 }
    }

    private var shownMonth: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var calendarHeader: some View {
        HStack(spacing: 4) {
            Button {
                monthOffset = 0
                viewModel.setCalendarExpanded(false)
            } label: {
                HStack(spacing: 6) {
                    Text(shownMonth.formatted(.dateTime.month(.wide).year()))
                        .font(Theme.Typography.title)
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
