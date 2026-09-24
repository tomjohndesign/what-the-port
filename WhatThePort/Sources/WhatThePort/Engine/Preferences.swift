import Foundation

/// UserDefaults keys and defaults for every setting. Views bind with
/// `@AppStorage(Preferences.x)`, the engine reads through `Preferences.value`.
enum Preferences {
    // General
    static let iconStyle = "general.iconStyle"
    static let editor = "general.editor"
    static let terminal = "general.terminal"
    static let hotkey = "general.hotkey"
    static let scanInterval = "general.scanInterval"
    static let onboarded = "general.onboarded"

    // Alerts
    static let thresholdGB = "alerts.thresholdGB"
    static let leakWarnings = "alerts.leakWarnings"
    static let snoozeMinutes = "alerts.snoozeMinutes"
    static let startStop = "alerts.startStop"

    // Clean up
    static let cleanUpMode = "cleanup.mode"
    static let cleanUpNotify = "cleanup.notify"
    static let cleanUpDeletedWorktree = "cleanup.deletedWorktree"
    static let cleanUpIdleHours = "cleanup.idleHours"
    static let cleanUpRunningDays = "cleanup.runningDays"
    static let protectedProcesses = "cleanup.protected"
    static let forceQuitSeconds = "cleanup.forceQuitSeconds"

    // Integrations
    static let linkClaude = "integrations.claude"
    static let linkCodex = "integrations.codex"
    static let linkConductor = "integrations.conductor"
    static let showBranches = "integrations.branches"
    static let vercelPreviews = "integrations.vercelPreviews"
    static let githubPullRequests = "integrations.githubPullRequests"

    enum IconStyle: String, CaseIterable {
        case colon, colonCount, count
        var label: String {
            switch self {
            case .colon: return "Colon"
            case .colonCount: return "Colon + count"
            case .count: return "Count"
            }
        }
    }

    enum CleanUpMode: String, CaseIterable {
        case off, ask, automatic
        var label: String { rawValue == "off" ? "Off" : rawValue == "ask" ? "Ask" : "Automatic" }
    }

    static let defaultProtected = ["postgres", "redis-server", "mongod", "mysqld", "mysql"]

    static func register() {
        UserDefaults.standard.register(defaults: [
            iconStyle: IconStyle.colonCount.rawValue,
            editor: "auto",
            terminal: "com.apple.Terminal",
            hotkey: true,
            scanInterval: 2.0,
            thresholdGB: 2.0,
            leakWarnings: true,
            snoozeMinutes: 60,
            startStop: false,
            cleanUpMode: CleanUpMode.ask.rawValue,
            cleanUpNotify: true,
            cleanUpDeletedWorktree: true,
            cleanUpIdleHours: 4,
            cleanUpRunningDays: 3,
            protectedProcesses: defaultProtected,
            forceQuitSeconds: 3.0,
            linkClaude: true,
            linkCodex: true,
            linkConductor: true,
            showBranches: true,
            // Both make network calls through `gh`, so they're opt-in.
            vercelPreviews: false,
            githubPullRequests: false,
        ])
    }

    static var defaults: UserDefaults { .standard }
}
