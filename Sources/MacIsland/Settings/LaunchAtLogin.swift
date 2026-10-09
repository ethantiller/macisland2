import ServiceManagement

/// Start MacIsland when you log in. Only works from the bundled app (`build/MacIsland.app`).
enum LaunchAtLogin {
    /// What the last look found. `SMAppService.status` is a synchronous call that takes about 150 ms, so it is made once, and again
    /// off the main thread by `reload()`.
    nonisolated(unsafe) private static var known: Bool?

    static var isEnabled: Bool {
        if let known { return known }
        let value = SMAppService.mainApp.status == .enabled
        known = value
        return value
    }

    /// Looks again without holding the main thread, for when the person may have changed Login Items in System Settings.
    static func reload() async -> Bool {
        let value = await Task.detached(priority: .utility) { SMAppService.mainApp.status == .enabled }.value
        known = value
        return value
    }

    /// Returns the state after the change; it stays `false` if macOS refuses (unsigned or unbundled).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("MacIsland: launch at login failed: \(error.localizedDescription)")
        }
        // Registered but waiting on the user: take them to the switch.
        if enabled, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        known = nil
        return isEnabled
    }
}
