import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        // Run as `wtp` (a symlink to this binary) or with --tui for the terminal UI.
        if TerminalCommand.isRequested { TerminalCommand.run() }
        WhatThePortApp.main()
    }
}

struct WhatThePortApp: App {
    @StateObject private var monitor: ServerMonitor

    init() {
        FontLoader.registerBundledFonts()
        Preferences.register()
        // Initialize AppKit for snapshot mode without overriding its appearance.
        _ = NSApplication.shared
        let monitor = ServerMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot-onboarding") {
            let directory = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
            SnapshotRenderer.runOnboarding(monitor: monitor, directory: directory)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let directory = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
            SnapshotRenderer.run(monitor: monitor, directory: directory)
        }
        _ = AppUpdater.shared
        AlertCenter.shared.start(monitor: monitor)
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Preferences.hotkey))
        monitor.start()
        Usage.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRoot(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)

        Window("Welcome to WhatThePort", id: "onboarding") {
            OnboardingContainer(monitor: monitor)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

struct OnboardingContainer: View {
    @ObservedObject var monitor: ServerMonitor
    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage(Preferences.onboarded) private var onboarded = false

    var body: some View {
        // People updating from before usage sharing only see that step.
        OnboardingView(monitor: monitor, step: onboarded ? .usage : .welcome, usageOnly: onboarded,
                       close: { dismissWindow(id: "onboarding") })
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: ServerMonitor
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.colonCount.rawValue
    @AppStorage(Preferences.onboarded) private var onboarded = false
    @AppStorage(Preferences.usageAsked) private var usageAsked = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = monitor.servers.count
        let style = Preferences.IconStyle(rawValue: iconStyle) ?? .colonCount
        let (glyph, label): (DotGlyph, Int?) = {
            if count == 0 { return (.idle, nil) }
            if monitor.needsAttention { return (.alert, style == .colon ? nil : count) }
            switch style {
            case .colon: return (.colon, nil)
            case .colonCount: return (.colon, count)
            case .count: return DotGlyph.digit(count).map { ($0, nil) } ?? (.colon, count)
            }
        }()
        Image(nsImage: MenuBarIcon.image(glyph: glyph, count: label))
            .accessibilityLabel(count == 0 ? "WhatThePort, no servers" : "WhatThePort, \(count) servers")
            .task {
                StatusItemMenu.install(monitor: monitor) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                // First launch: show onboarding once. After updating, ask about usage once.
                guard !onboarded || !usageAsked, Bundle.main.bundleURL.pathExtension == "app" else { return }
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
    }
}
