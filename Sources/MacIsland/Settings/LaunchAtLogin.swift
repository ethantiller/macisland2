import ServiceManagement

/// Start MacIsland when you log in. Only works from the bundled app (`build/MacIsland.app`).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
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
        return isEnabled
    }
}
