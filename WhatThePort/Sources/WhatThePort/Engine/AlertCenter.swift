import AppKit
import UserNotifications

/// Watches scans for servers that need attention and posts notifications with
/// Details / Stop / Snooze actions. Each alert fires once and re-arms only after
/// the condition clears, so a server hovering around the threshold doesn't nag.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    private enum Kind: String { case memory, leak }
    private enum Action {
        static let category = "server-alert"
        static let details = "details"
        static let stop = "stop"
        static let snooze = "snooze"
    }

    /// How long a server must stay over the threshold before we alert.
    private let sustainFor: TimeInterval = 30

    private weak var monitor: ServerMonitor?
    private var fired: [String: Set<Kind>] = [:]
    private var overSince: [String: Date] = [:]
    private var snoozedUntil: [Int: Date] = [:]
    private var knownPorts: Set<Int>?

    /// Notifications need a real app bundle; `swift run` and snapshot mode don't have one.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func start(monitor: ServerMonitor) {
        self.monitor = monitor
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.details, title: "Details", options: [.foreground]),
            UNNotificationAction(identifier: Action.stop, title: "Stop", options: [.destructive]),
            UNNotificationAction(identifier: Action.snooze, title: "Snooze", options: []),
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: Action.category, actions: actions, intentIdentifiers: [])])
        // Before onboarding, the Leaks step asks with context instead.
        guard UserDefaults.standard.bool(forKey: Preferences.onboarded) else { return }
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(_ servers: [Server], threshold: UInt64) {
        let defaults = UserDefaults.standard
        let now = Date()
        var liveKeys = Set<String>()

        for server in servers where !server.isProtected {
            let key = "\(server.port)-\(server.rootPid)"
            liveKeys.insert(key)
            var kinds = fired[key] ?? []

            // Memory over threshold, sustained. Re-arm below 90% to avoid flapping.
            if server.memory >= threshold {
                let since = overSince[key] ?? now
                overSince[key] = since
                if now.timeIntervalSince(since) >= sustainFor, !kinds.contains(.memory) {
                    kinds.insert(.memory)
                    post(server, kind: .memory,
                         title: ":\(server.port) \(server.project.name) is using \(Format.bytesString(server.memory))",
                         body: "That's over your \(MemoryChart.trim(Double(threshold) / Format.gigabyte)) GB alert. \(context(for: server))")
                }
            } else if Double(server.memory) < Double(threshold) * 0.9 {
                overSince[key] = nil
                kinds.remove(.memory)
            }

            // Fast growth. Re-arm once growth drops back under half the trigger.
            if defaults.bool(forKey: Preferences.leakWarnings), server.isLeaking(), !kinds.contains(.leak) {
                kinds.insert(.leak)
                let window = server.history.first.map { Format.duration(now.timeIntervalSince($0.time)) } ?? "10m"
                post(server, kind: .leak,
                     title: ":\(server.port) \(server.project.name) is leaking",
                     body: "\(server.project.framework ?? "It") grew \(Format.bytesString(UInt64(max(server.memoryGrowth, 0)))) in \(window) and is now using \(Format.bytesString(server.memory)).")
            } else if server.memoryGrowth < 250_000_000 {
                kinds.remove(.leak)
            }

            fired[key] = kinds
        }

        fired = fired.filter { liveKeys.contains($0.key) }
        overSince = overSince.filter { liveKeys.contains($0.key) }
        snoozedUntil = snoozedUntil.filter { $0.value > now }
        announceStartStop(servers)
    }

    // MARK: - Posting

    private func post(_ server: Server, kind: Kind, title: String, body: String) {
        guard isAvailable else { return }
        if let until = snoozedUntil[server.port], until > Date() { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Action.category
        content.threadIdentifier = "port-\(server.port)"
        content.userInfo = ["port": server.port]
        let request = UNNotificationRequest(identifier: "\(kind.rawValue)-\(server.port)-\(server.rootPid)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        Usage.record(.memoryAlert)
    }

    private func announceStartStop(_ servers: [Server]) {
        let ports = Set(servers.map(\.port))
        defer { knownPorts = ports }
        guard let known = knownPorts, isAvailable, UserDefaults.standard.bool(forKey: Preferences.startStop) else { return }
        for server in servers where !known.contains(server.port) {
            let content = UNMutableNotificationContent()
            content.title = ":\(server.port) \(server.project.name) started"
            content.body = context(for: server)
            content.userInfo = ["port": server.port]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "start-\(server.port)", content: content, trigger: nil))
        }
        for port in known.subtracting(ports) {
            let content = UNMutableNotificationContent()
            content.title = ":\(port) stopped"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stop-\(port)", content: content, trigger: nil))
        }
    }

    /// Clean up: "3 servers can be cleaned up" (Ask) or "Stopped 3 servers" (Automatic).
    func announceCleanUp(_ servers: [Server], stopped: Bool) {
        guard isAvailable, !servers.isEmpty else { return }
        let content = UNMutableNotificationContent()
        let names = servers.map { ":\($0.port) \($0.project.name)" }.joined(separator: ", ")
        let count = servers.count == 1 ? "1 server" : "\(servers.count) servers"
        content.title = stopped ? "Stopped \(count)" : "\(count) can be cleaned up"
        content.body = names + " · " + Format.bytesString(servers.reduce(0) { $0 + $1.memory }) + (stopped ? " freed" : "")
        if servers.count == 1 { content.userInfo = ["port": servers[0].port] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cleanup-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    private func context(for server: Server) -> String {
        [server.project.branch, server.agent.map { "\($0.kind.rawValue) session" }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let port = response.notification.request.content.userInfo["port"] as? Int
        let action = response.actionIdentifier
        Task { @MainActor in
            self.handle(action: action, port: port)
            completionHandler()
        }
    }

    private func handle(action: String, port: Int?) {
        guard let monitor else { return }
        guard let port else {
            StatusItemOpener.open()
            return
        }
        switch action {
        case Action.stop:
            if let server = monitor.server(port: port) {
                Usage.record(.stop)
                monitor.stop(server)
            }
        case Action.snooze:
            let minutes = UserDefaults.standard.integer(forKey: Preferences.snoozeMinutes)
            snoozedUntil[port] = Date().addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
        default:
            // Details, or a click on the notification itself.
            monitor.pendingRoute = .detail(port: port)
            StatusItemOpener.open()
        }
    }
}

/// MenuBarExtra has no API to open its window, so find the status item button
/// and click it. Look in every window rather than a private window class:
/// macOS 27 draws the menu bar as one window instead of one per icon.
@MainActor
enum StatusItemOpener {
    /// Returns false when there's no icon to click.
    @discardableResult
    static func open() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let button else { return false }
        button.performClick(nil)
        return true
    }

    /// Whether the icon is on screen. The menu bar can hide it: in its overflow
    /// on macOS 27, behind the notch, or when it's turned off in System
    /// Settings → Menu Bar.
    static var isShowing: Bool {
        guard let window = button?.window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    private static var button: NSStatusBarButton? {
        NSApp.windows.lazy.compactMap { findButton(in: $0.contentView) }.first
    }

    static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}
