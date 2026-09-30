import AppKit

@MainActor
enum SystemActions {
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    static func pickColor(completion: @escaping (NSColor) -> Void) {
        NSColorSampler().show { color in
            guard let color else { return }
            completion(color)
        }
    }

    static func hexString(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    static func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// Interactive screenshot of a selected area, copied to the clipboard.
    /// Completion is `false` if the user cancelled.
    static func captureScreenshotToClipboard(completion: @escaping (Bool) -> Void) {
        let changeCount = NSPasteboard.general.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        process.terminationHandler = { _ in
            Task { @MainActor in
                completion(NSPasteboard.general.changeCount != changeCount)
            }
        }
        do {
            try process.run()
        } catch {
            completion(false)
        }
    }
}
