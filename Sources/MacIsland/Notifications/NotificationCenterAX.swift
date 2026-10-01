import AppKit
import ApplicationServices

/// A node of a live accessibility tree. Every read is a call to another process, with a short timeout set on the application element.
struct AXElementNode: AXNodeReading, @unchecked Sendable {
    let element: AXUIElement

    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ name: String) -> String? { attribute(name) as? String }

    var role: String? { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }
    var identifier: String? { string(kAXIdentifierAttribute) }
    var value: String? { string(kAXValueAttribute) ?? string(kAXTitleAttribute) ?? string(kAXDescriptionAttribute) }

    var children: [any AXNodeReading] {
        guard let list = attribute(kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return list.map { AXElementNode(element: $0) }
    }

    var actions: [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    var position: CGPoint? {
        guard let value = attribute(kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    @discardableResult func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    @discardableResult func setPosition(_ point: CGPoint) -> Bool {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }
}

/// The listener on Notification Center's process. It is told when a window appears or goes, or the layout of one changes, and it
/// follows the process if it restarts.
@MainActor
final class NotificationCenterObserver {
    static let bundleIdentifier = "com.apple.notificationcenterui"

    private var observer: AXObserver?
    private var application: AXUIElement?
    private var onChange: (@MainActor () -> Void)?
    private var launchToken: NSObjectProtocol?

    /// Notification Center's tree, or nil when its process isn't there.
    var root: (any AXNodeReading)? { application.map { AXElementNode(element: $0) } }

    /// Starts listening. False when the process can't be found or listened to, which is what the Accessibility tree of a macOS that
    /// changed this looks like.
    func start(onChange: @escaping @MainActor () -> Void) -> Bool {
        self.onChange = onChange
        guard attach() else { return false }
        if launchToken == nil {
            launchToken = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleIdentifier else { return }
                MainActor.assumeIsolated {
                    if self?.attach() == true { self?.onChange?() }
                }
            }
        }
        return true
    }

    func stop() {
        detach()
        if let launchToken { NSWorkspace.shared.notificationCenter.removeObserver(launchToken) }
        launchToken = nil
        onChange = nil
    }

    private func attach() -> Bool {
        detach()
        guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first
        else { return false }
        let element = AXUIElementCreateApplication(process.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<NotificationCenterObserver>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.onChange?() }
        }
        guard AXObserverCreate(process.processIdentifier, callback, &created) == .success, let created else {
            return false
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var added = 0
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            if AXObserverAddNotification(created, element, name as CFString, refcon) == .success { added += 1 }
        }
        guard added > 0 else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        application = element
        return true
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
    }
}

extension NotificationReader.Environment {
    /// The Mac's own Notification Center.
    @MainActor
    static func live(observer: NotificationCenterObserver = NotificationCenterObserver()) -> Self {
        Self(
            hasAccess: { AXIsProcessTrusted() },
            root: { observer.root },
            observe: { observer.start(onChange: $0) },
            stopObserving: { observer.stop() },
            isCenterOpen: {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == NotificationCenterObserver.bundleIdentifier
            },
            openApp: { NotificationCenterApps.open(named: $0) },
            closeNames: NotificationCenterApps.closeNames,
            dumpsTree: ProcessInfo.processInfo.environment["MACISLAND_NOTIFICATION_DEBUG"] != nil)
    }
}

enum NotificationCenterApps {
    /// "Close" in the language Notification Center uses, read from its own strings (the English word is always accepted).
    static var closeNames: Set<String> {
        var names: Set<String> = ["Close"]
        if let bundle = Bundle(path: "/System/Library/CoreServices/NotificationCenter.app") {
            let translated = bundle.localizedString(forKey: "Close", value: nil, table: nil)
            if !translated.isEmpty { names.insert(translated) }
        }
        return names
    }

    /// Opens the app a banner names (the banner has its name, not its bundle identifier): a running one is brought forward, else one
    /// installed in the usual places.
    @MainActor
    static func open(named name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
            return running.activate()
        }
        let folders = [
            "/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        for folder in folders {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".app")
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
        }
        return false
    }
}
