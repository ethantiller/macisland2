import SwiftUI

/// Hover: the top live activity at full size, without the tab strip. A click opens the island.
struct PeekContent: View {
    let viewModel: IslandViewModel

    var body: some View {
        Group {
            switch viewModel.compactActivity {
            case .media:
                NowPlayingView(nowPlaying: viewModel.nowPlaying, outputs: viewModel.outputs, bluetooth: viewModel.bluetooth, isPeek: true)
            case .timer, .pomodoro, .stopwatch:
                ClockPeekView(viewModel: viewModel)
            default:
                IdlePeekView(viewModel: viewModel)
            }
        }
        .frame(height: viewModel.peekContentHeight, alignment: .top)
        .padding(.horizontal, ScreenGeometry.topFlare + Theme.Metrics.margin)
        .padding(.top, viewModel.geometry.notchSize.height + Theme.Metrics.contentTopGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Hover with nothing live: the day at a glance, and the everyday controls within reach.
struct IdlePeekView: View {
    let viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                DateInline()
                if let conditions = viewModel.weather.conditions {
                    WeatherGlance(conditions: conditions)
                }
                Spacer(minLength: 0)
                if let next = viewModel.agenda.next {
                    UpNextLabel(item: next, emptyTitle: "")
                } else {
                    MacBatteryGlance()
                }
            }
            .frame(height: 44)

            HStack(spacing: 12) {
                QuickToolsRow(viewModel: viewModel)
                Spacer(minLength: 0)
                QuickTimerChips(viewModel: viewModel, showsPomodoro: false)
            }
            .frame(height: Theme.Metrics.homeQuickHeight)
        }
    }
}
