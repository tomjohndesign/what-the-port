import Foundation

/// Anonymous usage: whether the app ran today and which features were used,
/// by name only. Once a day it requests one URL per feature from the website,
/// with no body, cookies or identifier, so the site's request counts add up to
/// installs per feature. Nothing about servers, projects, paths or this Mac is
/// recorded. Turning the setting off sends nothing and discards anything pending.
enum Usage {
    enum Feature: String, CaseIterable {
        case active             // The app ran
        case popover            // Opened the popover
        case shortcut           // Opened it with ⌥⌘P
        case details            // Opened a server's details
        case openBrowser = "open-browser"
        case openEditor = "open-editor"
        case stop
        case restart
        case cleanUp = "clean-up"
        case autoCleanUp = "auto-clean-up"
        case memoryAlert = "memory-alert"
        case resumeSession = "resume-session"
        case vercelPreview = "vercel-preview"
        case pullRequest = "pull-request"
    }

    private static let pendingKey = "usage.pending"
    private static let lastSentKey = "usage.lastSent"
    private static let interval: TimeInterval = 86_400
    private static var timer: Timer?

    static var isSharing: Bool { UserDefaults.standard.bool(forKey: Preferences.shareUsage) }

    static func record(_ feature: Feature) {
        guard isSharing, endpoint != nil else { return }
        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        if pending.insert(feature.rawValue).inserted {
            UserDefaults.standard.set(pending.sorted(), forKey: pendingKey)
        }
    }

    static func setSharing(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Preferences.shareUsage)
        if !enabled { UserDefaults.standard.removeObject(forKey: pendingKey) }
    }

    /// Checks hourly and reports at most once a day.
    static func start() {
        guard endpoint != nil, timer == nil else { return }
        record(.active)
        sendIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            record(.active)
            sendIfDue()
        }
    }

    /// Only release builds with an update feed report, to the feed's website.
    /// Local builds, `swift run` and snapshots never do.
    private static var endpoint: URL? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              !CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") }),
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", let host = url.host else { return nil }
        return URL(string: "https://\(host)/usage/")
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        // Replaces the default agent, which names the Darwin and CFNetwork versions.
        configuration.httpAdditionalHeaders = ["User-Agent": "WhatThePort/\(version)"]
        return URLSession(configuration: configuration)
    }()

    private static func sendIfDue() {
        let defaults = UserDefaults.standard
        // Nothing leaves the Mac until the choice has been offered.
        guard isSharing, defaults.bool(forKey: Preferences.usageAsked), let endpoint else { return }
        if let last = defaults.object(forKey: lastSentKey) as? Date, Date().timeIntervalSince(last) < interval { return }
        let features = (defaults.stringArray(forKey: pendingKey) ?? []).filter { Feature(rawValue: $0) != nil }
        guard !features.isEmpty else { return }
        defaults.set(Date(), forKey: lastSentKey)
        defaults.removeObject(forKey: pendingKey)
        for feature in features {
            session.dataTask(with: endpoint.appendingPathComponent(feature)).resume()
        }
    }
}
