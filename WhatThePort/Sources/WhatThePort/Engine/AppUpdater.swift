import AppKit
import Combine
import Sparkle

/// Owns one updater for the app's lifetime. Sparkle persists preferences and
/// handles scheduling, signature verification, installation and relaunching.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var unavailableReason: String?

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
        guard !CommandLine.arguments.contains("--snapshot"),
              Bundle.main.bundleURL.pathExtension == "app" else {
            unavailableReason = "Updates are available in the installed app."
            return
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = "Automatic updates aren’t configured for this build."
            return
        }

        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyDownloadsUpdates)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastUpdateCheckDate)
        do {
            try updater.start()
        } catch {
            unavailableReason = "The updater couldn’t start: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = enabled
    }

    // Make update windows discoverable for this otherwise dockless app without
    // stealing focus when a scheduled update is found in the background.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.regular)
            if !state.userInitiated { NSApp.dockTile.badgeLabel = "1" }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { NSApp.dockTile.badgeLabel = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            NSApp.dockTile.badgeLabel = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
