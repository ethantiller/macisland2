import AppKit
import SwiftUI

// The widgets beyond Home's first four (HomeWidgets.swift): weather, battery, reminders, a note, and the ones the
// person made. Each takes the size it is placed at and draws that size's own layout, inside a `widgetBox()`.

// MARK: Weather

/// "1 PM" for an hour of the day, in this Mac's own clock style.
enum WeatherText {
    static func hour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    static func range(_ day: WeatherDay) -> String { "\(day.high)° / \(day.low)°" }
}

/// The weather: 1 by 1 is the symbol and temperature over the place; wider adds the condition, then the high and
/// low; 6 by 1 is now and the next five hours; 3 by 2 is now and five days.
struct WeatherWidget: View {
    let viewModel: IslandViewModel
    var size = GridSize(1, 1)

    var body: some View {
        Group {
            if let conditions = viewModel.weather.conditions {
                forecast(conditions)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "cloud.sun")
                        .font(Theme.Typography.glyph)
                        .foregroundStyle(Theme.Palette.secondary)
                        .accessibilityHidden(true)
                    Text("Set a City")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
        }
        .padding(.horizontal, size.columns == 1 ? 8 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
    }

    @ViewBuilder
    private func forecast(_ conditions: WeatherConditions) -> some View {
        if size.rows >= 2, !conditions.days.isEmpty {
            days(conditions)
        } else if size.columns >= 6, !conditions.hours.isEmpty {
            hours(conditions)
        } else if size.columns == 1 {
            VStack(spacing: 4) {
                WeatherGlance(conditions: conditions)
                Text(conditions.place)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    WeatherGlance(conditions: conditions)
                    Spacer(minLength: 8)
                    if size.columns >= 3, let today = conditions.days.first {
                        Text(WeatherText.range(today))
                            .font(Theme.Typography.numeral)
                            .foregroundStyle(Theme.Palette.secondary)
                    }
                }
                Text("\(conditions.place) \u{00B7} \(conditions.summary)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Now, then the next five hours.
    private func hours(_ conditions: WeatherConditions) -> some View {
        HStack(spacing: 0) {
            hourColumn("Now", conditions.symbol, conditions.temperature)
            ForEach(conditions.hours, id: \.hour) { hourColumn(WeatherText.hour($0.hour), $0.symbol, $0.temperature) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conditions.summary), \(conditions.temperature) degrees in \(conditions.place)")
    }

    private func hourColumn(_ label: String, _ symbol: String, _ temperature: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondary)
            WeatherSymbol(name: symbol)
            Text("\(temperature)°")
                .font(Theme.Typography.compactNumeral)
                .foregroundStyle(Theme.Palette.primary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    /// Now, then five days: each a line of the day, its symbol, and its high and low.
    private func days(_ conditions: WeatherConditions) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                WeatherGlance(conditions: conditions)
                Text("\(conditions.place) \u{00B7} \(conditions.summary)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 28)
            Rectangle()
                .fill(Theme.Palette.widgetEdge)
                .frame(height: 1)
                .padding(.bottom, 4)
            ForEach(conditions.days, id: \.label) { day in
                HStack(spacing: 8) {
                    Text(day.label)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .frame(width: 40, alignment: .leading)
                    WeatherSymbol(name: day.symbol)
                    Spacer(minLength: 0)
                    Text(WeatherText.range(day))
                        .font(Theme.Typography.numeral)
                        .foregroundStyle(Theme.Palette.primary)
                }
                .lineLimit(1)
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.bottom, 6)
    }
}

/// A forecast symbol, in color like the glance beside the tabs.
private struct WeatherSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .symbolRenderingMode(.multicolor)
            .frame(width: Theme.Metrics.glyphSlot)
            .accessibilityHidden(true)
    }
}

// MARK: Battery

/// This Mac's battery. Red when it is low and not charging: it needs you. 2 by 1 says whether it is charging.
struct BatteryWidget: View {
    var size = GridSize(1, 1)

    @State private var reading = BatteryMonitor.readInternalBattery()

    var body: some View {
        Group {
            if let reading {
                let isLow = reading.percent <= 20 && !reading.onAC
                let ink = isLow ? AnyShapeStyle(Theme.Tint.attention) : AnyShapeStyle(Theme.Palette.primary)
                let glyph = Image(systemName: BatteryMonitor.symbol(percent: reading.percent, onAC: reading.onAC))
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(ink)
                if size.columns >= 2 {
                    HStack(spacing: 10) {
                        glyph.accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(reading.percent)%")
                                .font(Theme.Typography.compactNumeral)
                                .foregroundStyle(ink)
                            Text(reading.onAC ? "Charging" : "On Battery")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                } else {
                    VStack(spacing: 4) {
                        glyph.accessibilityHidden(true)
                        Text("\(reading.percent)%")
                            .font(Theme.Typography.compactNumeral)
                            .foregroundStyle(ink)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "powerplug")
                        .font(Theme.Typography.glyph)
                        .foregroundStyle(Theme.Palette.secondary)
                        .accessibilityHidden(true)
                    Text("No Battery")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetBox()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            reading.map { "Battery \($0.percent) percent\($0.onAC ? ", charging" : "")" } ?? "No Battery"
        )
        .onAppear { reading = BatteryMonitor.readInternalBattery() }
    }
}

// MARK: Reminders

/// The first open reminders, checked off in place: two (with their due text from 3 by 1), or four from 3 by 2.
struct RemindersWidget: View {
    let viewModel: IslandViewModel
    var size = GridSize(3, 1)

    private var agenda: AgendaMonitor { viewModel.agenda }

    /// How many reminders a size shows.
    static func rowCount(for size: GridSize) -> Int { size.rows >= 2 ? 4 : 2 }

    var body: some View {
        VStack(spacing: 0) {
            if agenda.remindersDenied {
                Label("Reminders Access Is Off", systemImage: "checklist")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            } else if agenda.reminderRows.isEmpty {
                Label("All Caught Up", systemImage: "checkmark.circle")
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                    .lineLimit(1)
            } else {
                ForEach(agenda.reminderRows.prefix(Self.rowCount(for: size))) { row in
                    ReminderRowView(row: row, showsDue: size.columns >= 3) { agenda.complete(reminderID: row.id) }
                }
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size.rows >= 2 ? .topLeading : .leading)
        .padding(.top, size.rows >= 2 ? 6 : 0)
        .widgetBox()
        .task { await agenda.showReminderList() }
        .onDisappear { agenda.hideReminderList() }
    }
}

// MARK: Note

/// The first lines of a note: the title and one line at 2 by 1, two at 3 by 1, up to six from 3 by 2. Opens Notes on it.
struct NoteWidget: View {
    let viewModel: IslandViewModel
    let options: WidgetOptions
    var size = GridSize(3, 1)

    private var note: Note? {
        let notes = viewModel.notes.notes
        return notes.first { $0.id == options.noteID } ?? notes.max { $0.updated < $1.updated }
    }

    /// How many lines of the note follow its title.
    static func lineCount(for size: GridSize) -> Int {
        if size.rows >= 2 { return 6 }
        return size.columns <= 2 ? 1 : 2
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                if let note {
                    Text(note.title)
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.primary)
                        .lineLimit(1)
                    Text(Self.excerpt(of: note, separator: size.rows >= 2 ? "\n" : " "))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(Self.lineCount(for: size))
                        .multilineTextAlignment(.leading)
                } else {
                    Label("No Notes", systemImage: "note.text")
                        .font(Theme.Typography.bodyEmphasized)
                        .foregroundStyle(Theme.Palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, size.rows >= 2 ? 10 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: size.rows >= 2 ? .topLeading : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
        .widgetBox()
    }

    /// What follows the title line.
    static func excerpt(of note: Note, separator: String = " ") -> String {
        note.body.split(whereSeparator: \.isNewline).dropFirst().joined(separator: separator)
    }

    private func open() {
        if let note { viewModel.notes.selectedNoteID = note.id }
        viewModel.select(.notes)
    }
}

// MARK: Widgets the person made

/// A widget the person made: a glyph, its value, and its name. White, like everything on the island; blue only
/// while it updates and red only when an update fails, each beside its own glyph. At 1 by 1 the glyph sits over the value.
struct CustomWidgetView: View {
    let widget: CustomWidget
    let viewModel: IslandViewModel
    var size = GridSize(2, 1)

    private var values: CustomWidgetValues { viewModel.widgets }

    var body: some View {
        // Asked again only while Home is on screen: on appear, and when the value outlives its limit.
        TimelineView(
            .periodic(from: .now, by: TimeInterval(max(widget.maxAgeMinutes, CustomWidget.minimumMaxAge) * 60))
        ) {
            context in
            content
                .task { values.refreshIfStale(widget) }
                .onChange(of: context.date) { values.refreshIfStale(widget) }
        }
    }

    private var content: some View {
        let phase = values.state(for: widget.id)
        let value = values.value(for: widget.id)
        return Button(action: tap) {
            Group {
                if size.columns == 1 {
                    VStack(spacing: 4) {
                        glyph(phase)
                        Text(widget.isButton ? (phase == .updating ? "Running" : "Run") : (value?.text ?? "\u{2014}"))
                            .font(widget.isButton ? Theme.Typography.caption : Theme.Typography.compactNumeral)
                            .foregroundStyle(widget.isButton ? Theme.Palette.secondary : Theme.Palette.primary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 10) {
                        glyph(phase)
                        VStack(alignment: .leading, spacing: 2) {
                            if widget.isButton {
                                Text(widget.title)
                                    .font(Theme.Typography.bodyEmphasized)
                                    .foregroundStyle(Theme.Palette.primary)
                                Text(phase == .updating ? "Running" : "Run")
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Palette.secondary)
                            } else {
                                Text(value?.text ?? "\u{2014}")
                                    .font(Theme.Typography.largeNumeral)
                                    .foregroundStyle(Theme.Palette.primary)
                                    .contentTransition(.numericText())
                                Text(caption(phase: phase, value: value))
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(
                                        failed(phase)
                                            ? AnyShapeStyle(Theme.Tint.attention)
                                            : AnyShapeStyle(Theme.Palette.secondary))
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
        .widgetBox()
        .accessibilityLabel(widget.title)
        .accessibilityValue(value?.text ?? "No value")
    }

    private func failed(_ phase: CustomWidgetValues.Phase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    @ViewBuilder
    private func glyph(_ phase: CustomWidgetValues.Phase) -> some View {
        let symbol = failed(phase) ? "exclamationmark.triangle.fill" : widget.systemImage
        let ink: AnyShapeStyle =
            failed(phase)
            ? AnyShapeStyle(Theme.Tint.attention)
            : (phase == .updating ? AnyShapeStyle(Theme.Tint.working) : AnyShapeStyle(Theme.Palette.primary))
        Image(systemName: symbol)
            .font(Theme.Typography.glyph)
            .foregroundStyle(ink)
            .frame(width: Theme.Metrics.glyphSlot)
            .accessibilityHidden(true)
    }

    /// The name, or the reason it failed, or the second line it returned.
    private func caption(phase: CustomWidgetValues.Phase, value: WidgetValue?) -> String {
        if case .failed(let reason) = phase { return reason }
        return value?.detail ?? widget.title
    }

    private func tap() {
        switch widget.source {
        case .shortcut(let name, let showsResult):
            if showsResult { values.refresh(widget) } else { viewModel.runShortcut(name) }
        case .folder(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .web, .command:
            values.refresh(widget)
        }
    }
}
