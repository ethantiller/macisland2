import AppKit
import Observation
import SwiftUI

/// What a torn-off window's chrome reads and changes.
@MainActor
@Observable
final class DetachedPanelState {
    var keepsOnDesktop = false
}

/// Modules torn off into their own windows: one per module, resizable, on glass. "Keep on Desktop" drops
/// a window to just above the desktop icons.
@MainActor
final class FloatingPanels {
    private let viewModel: IslandViewModel
    private var panels: [IslandModule: (panel: FloatingGlassPanel, state: DetachedPanelState)] = [:]

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
    }

    func isOpen(_ module: IslandModule) -> Bool { panels[module] != nil }

    /// Opens the module's window, or brings it forward. A new window's top-left corner is under `point`.
    func open(_ module: IslandModule, at point: NSPoint? = nil) {
        if let existing = panels[module] {
            existing.panel.makeKeyAndOrderFront(nil)
            return
        }
        let state = DetachedPanelState()
        let panel = FloatingGlassPanel()
        let hosting = NSHostingView(
            rootView: DetachedModuleView(
                module: module,
                viewModel: viewModel,
                state: state,
                onClose: { [weak self] in self?.close(module) },
                onToggleDesktop: { [weak self] in self?.toggleDesktop(module) }
            ))
        hosting.sizingOptions = []
        panel.contentView = hosting

        let size = Self.initialSize(for: module, viewModel: viewModel)
        panel.setContentSize(size)
        panel.contentMinSize = CGSize(width: 340, height: 140)
        panel.setFrameOrigin(Self.origin(for: size, at: point))
        panels[module] = (panel, state)

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close(_ module: IslandModule) {
        panels[module]?.panel.close()
        panels[module] = nil
    }

    func closeAll() {
        for module in Array(panels.keys) { close(module) }
    }

    func toggleDesktop(_ module: IslandModule) {
        guard let entry = panels[module] else { return }
        entry.state.keepsOnDesktop.toggle()
        entry.panel.keepsOnDesktop = entry.state.keepsOnDesktop
    }

    /// The module's content plus the window's chrome and padding.
    static func initialSize(for module: IslandModule, viewModel: IslandViewModel) -> CGSize {
        let padding = 2 * Theme.Metrics.floatPadding
        return CGSize(
            width: Theme.Metrics.detachedWidth + padding,
            height: Theme.Metrics.detachedChromeHeight + viewModel.contentHeight(for: module) + padding
        )
    }

    private static func origin(for size: CGSize, at point: NSPoint?) -> NSPoint {
        let screen =
            NSScreen.screens.first { NSMouseInRect(point ?? NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? .zero
        var origin =
            point.map { NSPoint(x: $0.x - 40, y: $0.y - size.height + 20) }
            ?? NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        origin.x = min(max(origin.x, frame.minX), frame.maxX - size.width)
        origin.y = min(max(origin.y, frame.minY), frame.maxY - size.height)
        return origin
    }
}

/// A torn-off module: a small header (title, Keep on Desktop, Close) over the module, on Liquid Glass.
struct DetachedModuleView: View {
    let module: IslandModule
    let viewModel: IslandViewModel
    @Bindable var state: DetachedPanelState
    let onClose: () -> Void
    let onToggleDesktop: () -> Void

    var body: some View {
        VStack(spacing: Theme.Metrics.rowSpacing) {
            HStack(spacing: 4) {
                Label(module.title, systemImage: module.systemImage)
                    .font(Theme.Typography.bodyEmphasized)
                    .foregroundStyle(Theme.Palette.secondary)
                Spacer(minLength: 8)
                IconButton(
                    systemName: state.keepsOnDesktop ? "pin.fill" : "pin",
                    label: state.keepsOnDesktop ? "Stop Keeping on Desktop" : "Keep on Desktop",
                    size: 12,
                    isSelected: state.keepsOnDesktop,
                    action: onToggleDesktop
                )
                IconButton(systemName: "xmark", label: "Close \(module.title)", size: 12, action: onClose)
            }
            .frame(height: Theme.Metrics.detachedHeaderHeight)

            ModuleContent(module: module, viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .floatingGlass()
        .environment(\.islandSurface, .glass)
        .environment(\.isFloatingWindow, true)
    }
}
