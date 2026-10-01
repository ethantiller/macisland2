import SwiftUI

/// Home: the widgets (edited in the preview above), then where Up Next and the weather come from.
struct HomePane: View {
    let settings: AppSettings
    let features: IslandFeatures
    let preview: IslandPreviewModel?
    let editor: HomeEditor

    @State private var editing: CustomWidget?

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
                Button("Open Internet Accounts", action: AgendaMonitor.openInternetAccounts)
                    .tourAnchor(.calendarEvents)
            } header: {
                Text("Up Next").id(SettingsAnchor.upNext)
            } footer: {
                Text(
                    "Meetings (Calendar, in Features) and due reminders (Content, Reminders) show in Up Next on Home, and announce themselves as banners. Outlook, Google, and Exchange calendars come from Internet Accounts."
                )
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
        .sheet(item: $editing) { widget in
            CustomWidgetSheet(widget: widget) { saved in
                settings.saveCustomWidget(saved)
                features.widgets.forget(saved.id)
            }
        }
    }
}
