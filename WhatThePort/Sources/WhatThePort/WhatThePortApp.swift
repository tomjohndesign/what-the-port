import SwiftUI

@main
struct WhatThePortApp: App {
    @StateObject private var monitor: ServerMonitor

    init() {
        FontLoader.registerBundledFonts()
        // The design is dark-only; without this the popover's glass follows a
        // light system appearance and washes out behind the dark content.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let monitor = ServerMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let directory = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
            SnapshotRenderer.run(monitor: monitor, directory: directory)
        }
        monitor.start()
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
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        let count = monitor.servers.count
        let glyph: DotGlyph = count == 0 ? .idle : (monitor.needsAttention ? .alert : .colon)
        Image(nsImage: MenuBarIcon.image(glyph: glyph, count: count == 0 ? nil : count))
            .accessibilityLabel(count == 0 ? "WhatThePort, no servers" : "WhatThePort, \(count) servers")
    }
}
