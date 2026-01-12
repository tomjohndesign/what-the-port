import SwiftUI

@main
struct WhatThePortApp: App {
    @StateObject private var monitor = PortMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Image(systemName: "network")
        }

        Window("Settings", id: "settings") {
            SettingsView(monitor: monitor)
        }
        .windowResizability(.contentSize)
    }
}
