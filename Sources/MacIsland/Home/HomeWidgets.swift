import SwiftUI

// Home's blocks each sit in a quiet box: a very dark fill and a hairline edge, enough to tell them apart
// without standing out. Every box is flush to the same left and right edges, so the rows line up. Corners
// follow one continuous hierarchy: the island's 32, then `widgetRadius` (14, concentric with the island's
// margin) for the boxes, then `nestedRadius` (8) for what is inside them.

/// The box behind a Home widget.
private struct WidgetBox: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
        content
            .background(Theme.Palette.widget, in: shape)
            .overlay(shape.strokeBorder(Theme.Palette.widgetEdge, lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    fileprivate func widgetBox() -> some View { modifier(WidgetBox()) }
}

// MARK: Row 1: time and music

/// One widget: today on a single line (which opens the calendar), over what is next.
struct TimeWidget: View {
    let viewModel: IslandViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { viewModel.setCalendarExpanded(true) } label: {
                HStack(spacing: 6) {
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.primary)
                    Image(systemName: "chevron.down")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.tertiary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
            .accessibilityLabel("Show Calendar, \(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))")

            Rectangle()
                .fill(Theme.Palette.widgetEdge)
                .frame(height: 1)

            Button(action: openNext) {
                UpNextLabel(item: viewModel.agenda.next, emptyTitle: "All Clear")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
    }

    /// A meeting with a call link joins it; a reminder opens the Reminders tab.
    private func openNext() {
        guard let item = viewModel.agenda.next else { return }
        if let url = item.joinURL {
            NSWorkspace.shared.open(url)
        } else if item.kind == .reminder {
            viewModel.select(.reminders)
        }
    }
}

/// What's playing, with play and pause. Opens the Media tab.
struct MediaWidget: View {
    let viewModel: IslandViewModel

    private var nowPlaying: NowPlayingModel { viewModel.nowPlaying }

    var body: some View {
        HStack(spacing: 10) {
            if nowPlaying.state.hasMedia {
                ArtworkView(image: nowPlaying.artwork, size: 40, cornerRadius: Theme.Metrics.nestedRadius)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.state.title)
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.primary)
                    Text(nowPlaying.state.artist.isEmpty ? nowPlaying.state.album : nowPlaying.state.artist)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                IconButton(
                    systemName: nowPlaying.state.isPlaying ? "pause.fill" : "play.fill",
                    label: nowPlaying.state.isPlaying ? "Pause" : "Play",
                    action: nowPlaying.togglePlayPause
                )
            } else {
                Label("Not Playing", systemImage: "music.note")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBox()
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(.media) }
    }
}

// MARK: Row 2: actions

/// The four everyday tools as a 2 by 2 grid in one module. On is a white fill with a black glyph.
struct QuickActionsGrid: View {
    let viewModel: IslandViewModel

    var body: some View {
        let catalog = ToolCatalog(viewModel: viewModel)
        let tools = Array(viewModel.settings.visiblePinned.prefix(4))
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(tools.dropFirst(row * 2).prefix(2)) { id in
                        QuickToolButton(
                            item: catalog.item(for: id),
                            size: Theme.Metrics.homeGridButton,
                            restingFill: Theme.Palette.fillHover,
                            hoverFill: Theme.Palette.tertiary
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .widgetBox()
    }
}

/// What the action pill offers, from what is running.
enum HomeAction: Equatable, Identifiable {
    case timer(minutes: Int)
    case runningTimer
    case pomodoro
    case runningPomodoro
    case runningStopwatch
    case shelf(count: Int)

    var id: String {
        switch self {
        case .timer(let minutes): "timer\(minutes)"
        case .runningTimer: "runningTimer"
        case .pomodoro: "pomodoro"
        case .runningPomodoro: "runningPomodoro"
        case .runningStopwatch: "runningStopwatch"
        case .shelf: "shelf"
        }
    }

    /// Two quick timers and a Pomodoro, each replaced by its running clock while it runs; the stopwatch
    /// joins only while it runs; Shelf is always last.
    static func list(timerActive: Bool, pomodoroActive: Bool, stopwatchActive: Bool, shelfCount: Int) -> [HomeAction] {
        var actions: [HomeAction] = timerActive ? [.runningTimer] : [.timer(minutes: 5), .timer(minutes: 25)]
        actions.append(pomodoroActive ? .runningPomodoro : .pomodoro)
        if stopwatchActive { actions.append(.runningStopwatch) }
        actions.append(.shelf(count: shelfCount))
        return actions
    }
}

/// Timers and the Shelf as one segmented pill. Each segment stacks its glyph or number over a caption.
struct HomeActionPill: View {
    let viewModel: IslandViewModel

    var body: some View {
        let actions = HomeAction.list(
            timerActive: viewModel.timer.isActive,
            pomodoroActive: viewModel.pomodoro.isActive,
            stopwatchActive: viewModel.stopwatch.isActive,
            shelfCount: viewModel.shelf.items.count
        )
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Palette.fillHover)
                        .frame(width: 1)
                        .padding(.vertical, 14)
                }
                segment(for: action)
            }
        }
        .frame(maxHeight: .infinity)
        .widgetBox()
    }

    @ViewBuilder
    private func segment(for action: HomeAction) -> some View {
        switch action {
        case .timer(let minutes):
            PillSegment(caption: "min", accessibilityLabel: "Start \(minutes) Minute Timer") {
                Text("\(minutes)")
                    .font(Theme.Typography.largeNumeral)
                    .foregroundStyle(Theme.Palette.primary)
            } action: { viewModel.timer.start(minutes: minutes) }
        case .runningTimer:
            PillSegment(caption: "Timer", accessibilityLabel: "Timer") {
                CompactTimerText(timer: viewModel.timer)
            } action: { viewModel.openClock(.timer) }
        case .pomodoro:
            PillSegment(caption: "Pomodoro", accessibilityLabel: "Start Pomodoro") {
                Image(systemName: "brain.head.profile").font(Theme.Typography.glyph)
            } action: { viewModel.pomodoro.toggle() }
        case .runningPomodoro:
            PillSegment(caption: viewModel.pomodoro.phase.title, accessibilityLabel: "Pomodoro") {
                CompactPomodoroText(pomodoro: viewModel.pomodoro)
            } action: { viewModel.openClock(.pomodoro) }
        case .runningStopwatch:
            PillSegment(caption: "Stopwatch", accessibilityLabel: "Stopwatch") {
                CompactStopwatchText(stopwatch: viewModel.stopwatch)
            } action: { viewModel.openClock(.stopwatch) }
        case .shelf(let count):
            PillSegment(caption: count == 0 ? "Shelf" : "Shelf \(count)", accessibilityLabel: "Open Shelf") {
                Image(systemName: "tray.full").font(Theme.Typography.glyph)
            } action: { viewModel.select(.shelf) }
        }
    }
}

/// One segment: a glyph or number over a caption. Hover lights a rounded highlight inside the pill.
private struct PillSegment<Primary: View>: View {
    let caption: String
    let accessibilityLabel: String
    @ViewBuilder let primary: Primary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                primary
                    .foregroundStyle(Theme.Palette.primary)
                    .frame(height: 22)
                Text(caption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isHovering ? Theme.Palette.fill : Theme.Palette.none,
                in: RoundedRectangle(cornerRadius: Theme.Metrics.nestedRadius, style: .continuous)
            )
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}
