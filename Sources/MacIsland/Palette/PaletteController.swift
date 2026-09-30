import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows and hides the command palette: a floating glass panel hung below the notch, centered on it, that takes
/// the keyboard without activating the app. Esc, Return, and the arrow keys are read here so the query field
/// doesn't swallow them.
@MainActor
final class PaletteController {
    private let viewModel: IslandViewModel
    private let model: PaletteModel
    private var panel: FloatingGlassPanel?

    var onOpenSettings: (() -> Void)? {
        didSet { model.onOpenSettings = { [weak self] in self?.hide(); self?.onOpenSettings?() } }
    }

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        model = PaletteModel(viewModel: viewModel)
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()

        let geometry = viewModel.geometry
        let screen = geometry.screenFrame
        panel.pinnedTop = screen.maxY - geometry.notchSize.height - Theme.Metrics.floatGap
        panel.setFrame(
            CGRect(
                x: screen.midX - Theme.Metrics.paletteWidth / 2,
                y: screen.maxY - geometry.notchSize.height - Theme.Metrics.floatGap - 60,
                width: Theme.Metrics.paletteWidth,
                height: 60
            ),
            display: false
        )
        panel.makeKeyAndOrderFront(nil)

        // Apps and Shortcuts are read in the background; the results catch up when they arrive.
        Task {
            await viewModel.launch.loadApps()
            await viewModel.launch.refreshShortcuts()
            model.update()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> FloatingGlassPanel {
        let panel = FloatingGlassPanel(style: .palette)
        let controller = NSHostingController(rootView: PaletteView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        panel.contentViewController = controller

        panel.keyHandler = { [weak self] event in self?.handle(event) ?? false }
        // Clicking away closes it, except while a translation is asking the system for a language.
        panel.onResignKey = { [weak self] in
            guard let self, case .working = self.model.translation else { self?.hide(); return }
        }
        return panel
    }

    private func handle(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_DownArrow:
            model.moveSelection(1)
        case kVK_UpArrow:
            model.moveSelection(-1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.runSelected()
        default:
            return false
        }
        return true
    }
}
