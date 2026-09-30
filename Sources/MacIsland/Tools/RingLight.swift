import AppKit
import SwiftUI

/// The Mac's answer to the flashlight: a soft white glow around the screen edge, for lighting
/// your face on video calls. Brightness and width are adjustable.
@MainActor
@Observable
final class RingLight {
    private(set) var isOn = false
    var brightness: Double = 0.8
    var width: Double = 0.4

    @ObservationIgnored private var window: NSWindow?

    func toggle() {
        isOn ? hide() : show()
    }

    private func show() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // Just below the island so the island stays usable while the light is on.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.contentView = NSHostingView(rootView: RingLightView(light: self))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        isOn = true
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
        isOn = false
    }
}

private struct RingLightView: View {
    let light: RingLight

    var body: some View {
        let lineWidth = 24 + light.width * 120
        Rectangle()
            .strokeBorder(Color.white, lineWidth: lineWidth)
            .blur(radius: lineWidth * 0.3)
            .opacity(0.25 + light.brightness * 0.75)
            .ignoresSafeArea()
    }
}
