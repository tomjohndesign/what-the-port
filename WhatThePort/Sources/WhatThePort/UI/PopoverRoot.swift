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
    @State private var contentHeight: CGFloat = 0

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
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .background(PopoverWindowFitter(height: contentHeight))
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

/// MenuBarExtra only resizes its window to fit the page in apps built with the
/// macOS 26 SDK. Otherwise the window keeps its first height and clips taller
/// pages, such as a server's details. Resize it here in that case, keeping the
/// top edge under the menu bar.
private struct PopoverWindowFitter: NSViewRepresentable {
    let height: CGFloat

    final class Coordinator {
        var height: CGFloat = 0
        /// Learned from the first page change: whether SwiftUI starts resizing the window itself.
        var swiftUIResizes: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.height = height
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, Self.needsFit(window, coordinator) else { return }
            switch coordinator.swiftUIResizes {
            case true?:
                return
            case false?:
                Self.fit(window, coordinator)
            case nil:
                let start = window.frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard coordinator.swiftUIResizes == nil else { return }
                    coordinator.swiftUIResizes = window.frame != start
                    if coordinator.swiftUIResizes == false { Self.fit(window, coordinator) }
                }
            }
        }
    }

    private static func needsFit(_ window: NSWindow, _ coordinator: Coordinator) -> Bool {
        coordinator.height > 0 && abs(window.contentRect(forFrameRect: window.frame).height - coordinator.height) > 1
    }

    private static func fit(_ window: NSWindow, _ coordinator: Coordinator) {
        guard needsFit(window, coordinator) else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: content.width, height: coordinator.height)).height
        var frame = window.frame
        frame.origin.y = frame.maxY - target
        frame.size.height = target
        window.setFrame(frame, display: true)
    }
}
