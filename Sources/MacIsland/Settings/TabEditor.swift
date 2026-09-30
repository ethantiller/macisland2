import SwiftUI
import UniformTypeIdentifiers

/// What the Tabs pane does in the preview. The preview's tab strip is the canvas, and the tabs that are not shown wait in a
/// tray right under it, so both are on screen at once:
/// - drag a tab onto another tab to swap them, or a tab from the tray onto a tab to replace it (the replaced one goes to the tray);
/// - drag a tab onto the tray to hide it;
/// - click a tab to see it, or a tab in the tray to add it.
/// A tab can only replace a tab: there is no dropping into the side of the notch. The rule is `AppSettings.swapTab`.
@MainActor
@Observable
final class TabEditor {
    let settings: AppSettings
    @ObservationIgnored weak var preview: IslandPreviewModel?
    /// The tab being dragged, when the drag started here (so the hint can name both tabs).
    private(set) var dragging: IslandModule?
    /// The tab a dragged tab is over.
    private(set) var target: IslandModule?
    /// A dragged tab is over the tray.
    private(set) var isOverTray = false
    /// What the last action did ("Swapped Media and Notes."), until the next click or drag.
    private(set) var message: String?

    init(settings: AppSettings) { self.settings = settings }

    /// The hint the tab strip shows when nothing is being dragged.
    static let idleHint = "Drag a tab onto another to swap them, or from Not Shown onto one to replace it."

    /// Shows a tab's content in the preview.
    func select(_ module: IslandModule) {
        message = nil
        preview?.show(PreviewContext(presentation: .expanded, tab: module))
    }

    func beginDrag(_ module: IslandModule) {
        dragging = module
        message = nil
    }

    func setTarget(_ module: IslandModule, isTargeted: Bool) {
        if isTargeted {
            target = module
            message = nil
        } else if target == module {
            target = nil
        }
    }

    func setOverTray(_ targeted: Bool) {
        isOverTray = targeted
        if targeted { message = nil }
    }

    /// While a dragged tab is over something: what letting go does.
    var hint: String? {
        if isOverTray {
            guard let dragging, settings.isInTabs(dragging) else { return nil }
            return "Release to hide \(dragging.title)."
        }
        if let target {
            guard let dragging, dragging != target else { return "Release to swap with \(target.title)." }
            return settings.isInTabs(dragging)
                ? "Release to swap \(dragging.title) and \(target.title)."
                : "Release to replace \(target.title) with \(dragging.title)."
        }
        return message
    }

    // MARK: Dropping

    /// A tab dropped on a tab. Says what happened.
    @discardableResult
    func drop(_ dragged: IslandModule, onto module: IslandModule) -> Bool {
        target = nil
        dragging = nil
        let wasShown = settings.isInTabs(dragged)
        guard settings.swapTab(dragged, with: module) else { return false }
        message =
            wasShown
            ? "Swapped \(dragged.title) and \(module.title)."
            : "\(dragged.title) replaced \(module.title), which is now in Not Shown."
        preview?.show(PreviewContext(presentation: .expanded, tab: dragged))
        return true
    }

    @discardableResult
    func drop(_ items: [String], onto module: IslandModule) -> Bool {
        guard let dragged = items.first.flatMap(IslandModule.init(rawValue:)) else {
            target = nil
            return false
        }
        return drop(dragged, onto: module)
    }

    /// A tab dropped on the tray: it is hidden, unless it is the last one.
    @discardableResult
    func hide(_ dragged: IslandModule) -> Bool {
        isOverTray = false
        dragging = nil
        guard settings.isInTabs(dragged) else { return false }
        guard settings.tabs.count > 1 else {
            message = "There has to be at least one tab."
            return false
        }
        settings.setEnabled(dragged, false)
        guard !settings.isInTabs(dragged) else { return false }
        if preview?.viewModel.selectedTab == dragged, let first = settings.tabs.first { select(first) }
        message = "\(dragged.title) is now in Not Shown."
        return true
    }

    @discardableResult
    func hide(items: [String]) -> Bool {
        guard let dragged = items.first.flatMap(IslandModule.init(rawValue:)) else { return false }
        return hide(dragged)
    }

    /// A tab in the tray, clicked: it becomes a tab if there is room. When there isn't, it says how to make room.
    func add(_ module: IslandModule) {
        guard !settings.isInTabs(module) else { return }
        settings.setEnabled(module, true)
        if settings.isInTabs(module) {
            message = "\(module.title) is now a tab."
            preview?.show(PreviewContext(presentation: .expanded, tab: module))
        } else {
            message = "Tabs are full. Drag \(module.title) onto a tab to replace it."
        }
    }

    // MARK: Drops that arrive as providers

    /// Reads which tab a drop carries. Drops that began here already know; the list rows send it as text.
    func resolve(_ providers: [NSItemProvider], then handle: @escaping (IslandModule) -> Void) -> Bool {
        if let dragging {
            handle(dragging)
            return true
        }
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let module = IslandModule(rawValue: text) else { return }
            Task { @MainActor in handle(module) }
        }
        return true
    }
}

private struct TabEditorKey: EnvironmentKey {
    static let defaultValue: TabEditor? = nil
}

extension EnvironmentValues {
    /// Set only in the Settings preview while the Tabs pane is open: the tab strip then takes clicks and drags.
    var tabEditor: TabEditor? {
        get { self[TabEditorKey.self] }
        set { self[TabEditorKey.self] = newValue }
    }
}

/// A tab in the preview's strip while editing: draggable, and a drop target that swaps with the tab dropped on it.
struct TabEditing: ViewModifier {
    let tab: IslandModule
    let editor: TabEditor?

    func body(content: Content) -> some View {
        if let editor {
            content
                .onDrag {
                    editor.beginDrag(tab)
                    return NSItemProvider(object: tab.rawValue as NSString)
                }
                .overlay {
                    if editor.target == tab {
                        Capsule().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .onDrop(
                    of: [.plainText],
                    isTargeted: Binding(
                        get: { editor.target == tab }, set: { editor.setTarget(tab, isTargeted: $0) })
                ) { providers in
                    editor.resolve(providers) { editor.drop($0, onto: tab) }
                }
        } else {
            content
        }
    }
}

/// The tabs that are not shown, in a tray right under the preview so they can be seen and dragged at the same time as the tab
/// strip. Drag one onto a tab to replace it; drop a tab here to hide it; click one to add it.
struct NotShownTray: View {
    let editor: TabEditor

    private var hidden: [IslandModule] { editor.settings.hiddenModules }

    var body: some View {
        HStack(spacing: 10) {
            Text("Not Shown")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if hidden.isEmpty {
                Text("Every tab is shown. Drag a tab here to hide it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(hidden) { module in chip(module) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(editor.isOverTray ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    editor.isOverTray ? Color.accentColor : Color.primary.opacity(0.2),
                    style: StrokeStyle(lineWidth: editor.isOverTray ? 2 : 1, dash: [5, 4]))
        )
        .onDrop(of: [.plainText], isTargeted: Binding(get: { editor.isOverTray }, set: { editor.setOverTray($0) })) {
            providers in
            editor.resolve(providers) { editor.hide($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs that are not shown")
    }

    private func chip(_ module: IslandModule) -> some View {
        Label(module.title, systemImage: module.systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
            .contentShape(Capsule())
            .onDrag {
                editor.beginDrag(module)
                return NSItemProvider(object: module.rawValue as NSString)
            }
            .onTapGesture { editor.add(module) }
            .help("Drag onto a tab to replace it, or click to add it as a tab")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Add as a Tab") { editor.add(module) }
    }
}
