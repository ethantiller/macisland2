import SwiftUI

// Home's blocks each sit in a quiet box: a very dark fill and a hairline edge, enough to tell them apart
// without standing out. Every box is flush to the same left and right edges, so the rows line up. Corners
// follow one continuous hierarchy: the island's 32, then `widgetRadius` (14, concentric with the island's
// margin) for the boxes, then `nestedRadius` (8) for what is inside them.

/// The box behind a Home widget.
struct WidgetBox: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metrics.widgetRadius, style: .continuous)
        content
            .background(Theme.Palette.widget, in: shape)
            .overlay(shape.strokeBorder(Theme.Palette.widgetEdge, lineWidth: 1))
            .clipShape(shape)
    }
}

extension View {
    func widgetBox() -> some View { modifier(WidgetBox()) }
}

// MARK: Today, music, and tools

/// Today. Every size keeps the date line (it opens the month calendar) over what is next: the next item alone, the
/// next three, or the month itself.
struct TimeWidget: View {
    let viewModel: IslandViewModel
    var size = GridSize(3, 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dateLine
            Rectangle()
                .fill(Theme.Palette.widgetEdge)
                .frame(height: 1)
            switch size.rows {
            case 3: month
            case 2: upcoming
            default: next
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
    }

    private var dateLine: some View {
        Button {
            viewModel.setCalendarExpanded(true)
        } label: {
            HStack(spacing: 6) {
                Text(
                    Date().formatted(
                        size.columns <= 2
                            ? .dateTime.weekday(.abbreviated).day()
                            : .dateTime.weekday(.wide).month(.abbreviated).day())
                )
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
    }

    /// 2 by 1 and 3 by 1: the one thing that is next.
    private var next: some View {
        Button {
            open(viewModel.agenda.next)
        } label: {
            UpNextLabel(item: viewModel.agenda.next, emptyTitle: "All Clear")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
    }

    /// 3 by 2: the next three things, each its own row.
    private var upcoming: some View {
        let items = Array(viewModel.agenda.upcoming.prefix(3))
        return VStack(spacing: 0) {
            if items.isEmpty {
                next
            } else {
                ForEach(items) { item in
                    Button {
                        open(item)
                    } label: {
                        UpNextLabel(item: item, emptyTitle: "All Clear")
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IslandButtonStyle())
                }
            }
        }
    }

    /// 3 by 3: the month, inline. Filling the box under the date line.
    private var month: some View {
        MonthGridView(month: Date(), rowHeight: 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A meeting with a call link joins it; a reminder opens the Reminders tab.
    private func open(_ item: AgendaItem?) {
        guard let item else { return }
        if let url = item.joinURL {
            MeetingLink.join(url)
        } else if item.kind == .reminder {
            viewModel.select(.reminders)
        }
    }
}

/// What's playing. The player itself from 3 by 2 up; below that, art and the transport that fits. Opens the Media tab.
struct MediaWidget: View {
    let viewModel: IslandViewModel
    var size = GridSize(3, 1)

    private var nowPlaying: NowPlayingModel { viewModel.nowPlaying }

    var body: some View {
        Group {
            if !nowPlaying.state.hasMedia {
                Label("Not Playing", systemImage: "music.note")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size.rows > 1 ? .center : .leading)
                    .padding(.leading, size.rows > 1 ? 0 : 12)
            } else if size.rows > 1 {
                NowPlayingView(
                    nowPlaying: nowPlaying, outputs: viewModel.outputs, bluetooth: viewModel.bluetooth, isPeek: true,
                    inWidget: true
                )
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
            } else {
                row
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBox()
        .contentShape(Rectangle())
        .onTapGesture { viewModel.select(.media) }
    }

    /// 2 by 1: art, play, next. 3 by 1: art, the song, play. 6 by 1: art, the song, back, play, forward.
    private var row: some View {
        HStack(spacing: 10) {
            ArtworkView(image: nowPlaying.artwork, size: 40, cornerRadius: Theme.Metrics.nestedRadius)
            if size.columns >= 3 {
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
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                if size.columns >= 6 {
                    IconButton(systemName: "backward.fill", label: "Previous Track", action: nowPlaying.previousTrack)
                }
                IconButton(
                    systemName: nowPlaying.state.isPlaying ? "pause.fill" : "play.fill",
                    label: nowPlaying.state.isPlaying ? "Pause" : "Play",
                    action: nowPlaying.togglePlayPause
                )
                if size.columns == 2 || size.columns >= 6 {
                    IconButton(systemName: "forward.fill", label: "Next Track", action: nowPlaying.nextTrack)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
    }
}

/// The everyday tools. 1 by 1 is a 2 by 2 of round buttons; 2 by 1 a row of four and 3 by 1 a row of six; 6 by 1 is
/// eight named buttons, and 6 by 2 is every tool, as on the Tools tab.
struct QuickActionsGrid: View {
    let viewModel: IslandViewModel
    /// Tools of the person's choosing; nil follows the Tools row.
    var chosen: [ToolID]?
    var size = GridSize(1, 1)

    /// How many tools a size shows. 6 by 2 shows them all (`total`, which includes the person's own).
    static func toolCount(for size: GridSize) -> Int { toolCount(for: size, total: ToolID.allCases.count) }

    static func toolCount(for size: GridSize, total: Int) -> Int {
        if size.rows >= 2 { return total }
        switch size.columns {
        case ...2: return 4
        case 3: return 6
        default: return 8
        }
    }

    /// The tools a size shows: the person's (or the Tools row's) first, then others to fill it. 6 by 2 is the Tools
    /// tab's own order.
    /// `all` is every tool there is (`AppSettings.allTools`); a chosen tool that isn't in it (a Shortcut tool since removed) is left out.
    static func tools(
        for size: GridSize, chosen: [ToolID]?, pinned: [ToolID], all: [ToolID] = ToolID.allCases
    ) -> [ToolID] {
        if size.rows >= 2 { return all }
        let first = (chosen ?? pinned).filter(all.contains)
        let rest = all.filter { !first.contains($0) }
        return Array((first + rest).prefix(toolCount(for: size, total: all.count)))
    }

    var body: some View {
        let catalog = ToolCatalog(viewModel: viewModel)
        let tools = Self.tools(
            for: size, chosen: chosen, pinned: viewModel.settings.visiblePinned, all: viewModel.settings.allTools)
        Group {
            switch (size.columns, size.rows) {
            case (1, _):
                Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            ForEach(tools.dropFirst(row * 2).prefix(2)) { round(catalog.item(for: $0)) }
                        }
                    }
                }
            case (_, 2...):
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 6), spacing: 10) {
                    ForEach(tools) { ToolControlButton(tool: catalog.item(for: $0)) }
                }
            case (6..., _):
                HStack(spacing: 0) {
                    ForEach(tools) { ToolControlButton(tool: catalog.item(for: $0)) }
                }
            default:
                HStack(spacing: 8) {
                    ForEach(tools) { round(catalog.item(for: $0)) }
                }
            }
        }
        .padding(.horizontal, size.columns == 1 ? 8 : (size.columns >= 6 ? 4 : 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
    }

    private func round(_ item: ToolItem) -> some View {
        QuickToolButton(
            item: item, size: Theme.Metrics.homeGridButton, restingFill: Theme.Palette.fillHover,
            hoverFill: Theme.Palette.tertiary)
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

    /// How many of the four segments (timer, timer, Pomodoro, Shelf) a width has room for: 2 columns have the
    /// timers, 3 add Pomodoro, and 4 or more add Shelf.
    static func segments(forColumns columns: Int) -> Int { min(max(columns, 2), 4) }

    /// Two quick timers, a Pomodoro, and Shelf, as many as `segments` allows and the options keep. A running
    /// clock replaces its segment and is always shown; the stopwatch joins only while it runs; Shelf is always last.
    static func list(
        timerActive: Bool, pomodoroActive: Bool, stopwatchActive: Bool, shelfCount: Int,
        timerMinutes: [Int] = [5, 25], showsPomodoro: Bool = true, showsShelf: Bool = true, segments: Int = 4
    ) -> [HomeAction] {
        var actions: [HomeAction] = timerActive ? [.runningTimer] : timerMinutes.map { .timer(minutes: $0) }
        if pomodoroActive {
            actions.append(.runningPomodoro)
        } else if showsPomodoro, segments >= 3 {
            actions.append(.pomodoro)
        }
        if stopwatchActive { actions.append(.runningStopwatch) }
        if showsShelf, segments >= 4 { actions.append(.shelf(count: shelfCount)) }
        return actions
    }
}

/// Timers and the Shelf as one segmented pill. Each segment stacks its glyph or number over a caption.
struct HomeActionPill: View {
    let viewModel: IslandViewModel
    var options = WidgetOptions()
    var size = GridSize(5, 1)

    var body: some View {
        let actions = HomeAction.list(
            timerActive: viewModel.timer.isActive,
            pomodoroActive: viewModel.pomodoro.isActive,
            stopwatchActive: viewModel.stopwatch.isActive,
            shelfCount: viewModel.shelf.items.count,
            timerMinutes: options.timerMinutes ?? [5, 25],
            showsPomodoro: options.showsPomodoro ?? true,
            showsShelf: options.showsShelf ?? true,
            segments: HomeAction.segments(forColumns: size.columns)
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
            } action: {
                viewModel.timer.start(minutes: minutes)
            }
        case .runningTimer:
            PillSegment(caption: "Timer", accessibilityLabel: "Timer") {
                CompactTimerText(timer: viewModel.timer)
            } action: {
                viewModel.openClock(.timer)
            }
        case .pomodoro:
            PillSegment(caption: "Pomodoro", accessibilityLabel: "Start Pomodoro") {
                Image(systemName: "brain.head.profile").font(Theme.Typography.glyph)
            } action: {
                viewModel.pomodoro.toggle()
            }
        case .runningPomodoro:
            PillSegment(caption: viewModel.pomodoro.phase.title, accessibilityLabel: "Pomodoro") {
                CompactPomodoroText(pomodoro: viewModel.pomodoro)
            } action: {
                viewModel.openClock(.pomodoro)
            }
        case .runningStopwatch:
            PillSegment(caption: "Stopwatch", accessibilityLabel: "Stopwatch") {
                CompactStopwatchText(stopwatch: viewModel.stopwatch)
            } action: {
                viewModel.openClock(.stopwatch)
            }
        case .shelf(let count):
            PillSegment(caption: count == 0 ? "Shelf" : "Shelf \(count)", accessibilityLabel: "Open Shelf") {
                Image(systemName: "tray.full").font(Theme.Typography.glyph)
            } action: {
                viewModel.select(.shelf)
            }
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
