import SwiftUI

private struct ScrollAreaUpdateKey: EnvironmentKey {
    static let defaultValue: (UUID, CGRect?, AxisLock.Axis) -> Void = { _, _, _ in }
}

extension EnvironmentValues {
    var updateScrollArea: (UUID, CGRect?, AxisLock.Axis) -> Void {
        get { self[ScrollAreaUpdateKey.self] }
        set { self[ScrollAreaUpdateKey.self] = newValue }
    }
}

struct ScrollAreaModifier: ViewModifier {
    @Environment(\.updateScrollArea) private var updateScrollArea
    @State private var id = UUID()
    @State private var frame = CGRect.zero
    @State private var overflows = false

    let axis: AxisLock.Axis

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                self.frame = frame
                publish()
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                switch axis {
                case .horizontal: geometry.contentSize.width > geometry.containerSize.width
                case .vertical: geometry.contentSize.height > geometry.containerSize.height
                }
            } action: { _, overflows in
                self.overflows = overflows
                publish()
            }
            .onDisappear { updateScrollArea(id, nil, axis) }
    }

    private func publish() {
        updateScrollArea(id, overflows ? frame : nil, axis)
    }
}

extension View {
    func reportsScrollArea(_ axis: AxisLock.Axis) -> some View {
        modifier(ScrollAreaModifier(axis: axis))
    }
}