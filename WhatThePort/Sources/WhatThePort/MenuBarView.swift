import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var monitor: PortMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var started = false

    var body: some View {
        Group {
            if monitor.ports.isEmpty {
                Text("No ports running")
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitor.ports) { port in
                    Menu(portDisplayText(for: port)) {
                        Button("Open in Browser") {
                            openInBrowser(port: port.port)
                        }
                        Button("Copy URL") {
                            copyToClipboard("http://localhost:\(port.port)")
                        }
                        Divider()
                        Button("Stop Server") {
                            monitor.stopProcess(port)
                        }
                    }
                }
            }

            Divider()

            Button("Refresh") {
                monitor.scan()
            }
            .keyboardShortcut("r")

            Button("Settings...") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            guard !started else { return }
            started = true
            let defaults = UserDefaults.standard
            let min = defaults.integer(forKey: "minPort")
            let max = defaults.integer(forKey: "maxPort")
            monitor.minPort = min > 0 ? min : 3000
            monitor.maxPort = max > 0 ? max : 9999
            monitor.start()
        }
    }

    private func portDisplayText(for port: ListeningPort) -> String {
        let name = port.projectName ?? port.process
        let uptime = formatUptime(since: port.startTime)
        return ":\(port.port) \(name) • \(uptime)"
    }

    private func formatUptime(since startTime: Date) -> String {
        let elapsed = Date().timeIntervalSince(startTime)
        let seconds = Int(elapsed)

        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            let days = seconds / 86400
            let hours = (seconds % 86400) / 3600
            if hours > 0 {
                return "\(days)d \(hours)h"
            } else {
                return "\(days)d"
            }
        }
    }

    private func openInBrowser(port: Int) {
        if let url = URL(string: "http://localhost:\(port)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
