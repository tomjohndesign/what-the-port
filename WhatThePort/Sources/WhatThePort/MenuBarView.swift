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
                    Menu("\(port.port) - \(port.process)") {
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
