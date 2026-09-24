import SwiftUI

enum PopoverRoute: Equatable {
    case servers
    case detail(port: Int)
}

struct PopoverRoot: View {
    @ObservedObject var monitor: ServerMonitor
    @State var route: PopoverRoute = .servers
    /// Snapshot mode uses this to render the Clean up state.
    var startCleaning = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch route {
            case .servers:
                ServersView(monitor: monitor,
                            startCleaning: startCleaning,
                            openServer: { server in navigate(to: .detail(port: server.port)) },
                            openSettings: openSettings)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .detail(let port):
                if let server = monitor.server(port: port) {
                    ServerDetailView(server: server, monitor: monitor, back: { navigate(to: .servers) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    // The server went away while we were looking at it.
                    Color.clear.frame(height: 1).onAppear { navigate(to: .servers) }
                }
            }
        }
        .frame(width: Theme.popoverWidth)
        .onAppear {
            monitor.start()
            Usage.record(.popover)
            consumePendingRoute()
        }
        .onChange(of: monitor.pendingRoute) { _, _ in consumePendingRoute() }
    }

    private func consumePendingRoute() {
        guard let pending = monitor.pendingRoute else { return }
        monitor.pendingRoute = nil
        route = pending
    }

    private func navigate(to newRoute: PopoverRoute) {
        if case .detail = newRoute { Usage.record(.details) }
        withAnimation(.snappy(duration: 0.22)) { route = newRoute }
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}
