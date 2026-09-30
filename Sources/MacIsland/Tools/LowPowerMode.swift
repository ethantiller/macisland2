import Foundation
import Observation

/// macOS Low Power Mode. Changing it needs an administrator, so macOS asks for a password or Touch ID.
@MainActor
@Observable
final class LowPowerMode {
    private(set) var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled

    init() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isOn = ProcessInfo.processInfo.isLowPowerModeEnabled }
        }
    }

    func toggle() {
        let value = isOn ? 0 : 1
        let source = #"do shell script "/usr/bin/pmset -a lowpowermode \#(value)" with administrator privileges"#
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
