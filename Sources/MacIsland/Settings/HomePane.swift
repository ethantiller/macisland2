import SwiftUI

/// Home: the widgets (edited in the preview above), then where Up Next and the weather come from.
struct HomePane: View {
    let settings: AppSettings
    let features: IslandFeatures
    let preview: IslandPreviewModel?
    let editor: HomeEditor

    @State private var editing: CustomWidget?
    /// The accounts and their calendars, read when the pane opens and when Calendar is switched on.
    @State private var calendarGroups: [CalendarGroup] = []

    var body: some View {
        Form {
            WidgetGallery(editor: editor, preview: preview, editing: $editing)
            if let selection = editor.selection, let placement = editor.layout.placement(id: selection),
                let preview
            {
                WidgetInspector(
                    editor: editor, placement: placement, preview: preview.viewModel, notes: features.notes,
                    onEdit: { editing = $0 })
            }
            HomeLayoutEditor(editor: editor)
            Section {
                FeatureOffNote(settings: settings, feature: .calendar)
                Toggle("Time Left in the Current Event", isOn: Bindable(settings).showsTimeLeft)
                    .disabled(!settings.isOn(.calendar))
                Toggle("Count Down to Every Event", isOn: Bindable(settings).countsDownToEveryEvent)
                    .disabled(!settings.isOn(.calendar))
                Button("Open Internet Accounts", action: AgendaMonitor.openInternetAccounts)
                    .tourAnchor(.calendarEvents)
            } header: {
                Text("Up Next").id(SettingsAnchor.upNext)
            } footer: {
                Text(
                    "Meetings (Calendar, in Features) and due reminders (Content, Reminders) show in Up Next on Home, and announce themselves as banners. Time left keeps a meeting that is on until it ends. A countdown shows beside the notch in the hour before a meeting: for every one, or for those you right-click and Add Countdown. Outlook, Google, and Exchange calendars come from Internet Accounts."
                )
            }
            if settings.isOn(.calendar), !calendarGroups.isEmpty {
                Section {
                    ForEach(calendarGroups) { group in
                        Text(group.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ForEach(group.calendars) { calendar in
                            Toggle(
                                calendar.title,
                                isOn: Binding(
                                    get: { !settings.isCalendarHidden(calendar.id) },
                                    set: { settings.setCalendarHidden(calendar.id, !$0) }))
                        }
                    }
                } header: {
                    Text("Calendars").id(SettingsAnchor.calendars)
                } footer: {
                    Text(
                        "Only these calendars count for Up Next, the banner before a meeting, and the dots in the month. One you add later counts until you switch it off."
                    )
                }
            }
            Section {
                FeatureOffNote(settings: settings, feature: .weather)
                TextField("City", text: Bindable(settings).weatherCity, prompt: Text("Paris"))
                    .disabled(!settings.isOn(.weather))
            } header: {
                Text("Weather").id(SettingsAnchor.weather)
            } footer: {
                Text(
                    "Shown beside the tabs, in the idle peek, and in the Weather widget. Weather comes from Open-Meteo, which is sent only the city name. The unit follows macOS (System Settings, Language & Region)."
                )
            }
        }
        .formStyle(.grouped)
        .task(id: settings.showsCalendar) { calendarGroups = features.agenda.calendarGroups() }
        .sheet(item: $editing) { widget in
            CustomWidgetSheet(widget: widget) { saved in
                settings.saveCustomWidget(saved)
                features.widgets.forget(saved.id)
            }
        }
    }
}
