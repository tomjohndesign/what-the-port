import SwiftUI

struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openServer: (Server) -> Void
    let openSettings: () -> Void

    private let maxVisibleRows = 7
    /// Port whose memory-bar segment is under the pointer.
    @State private var focusedPort: Int?
    /// Clean up is a mode of this page: checkboxes slide in and the footer
    /// turns into Cancel / Stop.
    @State private var isCleaning: Bool
    @State private var selection: Set<Int> = []

    init(monitor: ServerMonitor, startCleaning: Bool = false, openServer: @escaping (Server) -> Void, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openServer = openServer
        self.openSettings = openSettings
        _isCleaning = State(initialValue: startCleaning)
        _selection = State(initialValue: startCleaning ? Self.suggestedSelection(monitor) : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            SectionDivider()
            if visibleServers.isEmpty {
                emptyState
            } else if visibleServers.count > maxVisibleRows {
                ScrollView { rows }.frame(height: CGFloat(maxVisibleRows) * 52 + 12)
            } else {
                rows
            }
            SectionDivider()
            footer
        }
    }

    /// Protected processes (databases) can't be stopped from Clean up, so hide them there.
    private var visibleServers: [Server] {
        isCleaning ? monitor.servers.filter { !$0.isProtected } : monitor.servers
    }

    private var selectedServers: [Server] {
        visibleServers.filter { selection.contains($0.port) }
    }

    // MARK: - Summary

    private var summary: some View {
        let focused = focusedPort.flatMap { monitor.server(port: $0) }
        let freed = selectedServers.reduce(UInt64(0)) { $0 + $1.memory }
        let total: (number: String, unit: String) = {
            if let focused { return Format.bytes(focused.memory) }
            if isCleaning { return Format.total(freed) }
            return Format.total(monitor.totalMemory)
        }()
        return VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: isCleaning ? "Clean up" : "Servers")
            HStack(alignment: .center) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(total.number).font(Theme.display).foregroundStyle(Theme.text1)
                        .contentTransition(.numericText())
                    Text(total.unit).font(Theme.mono).foregroundStyle(Theme.text3)
                }
                Spacer()
                if let focused {
                    let share = Double(focused.memory) / Double(max(monitor.totalMemory, 1)) * 100
                    Text(":\(String(focused.port)) · \(Format.percent(share)) of total · CPU \(Format.percent(focused.cpu))")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.text2)
                } else if isCleaning {
                    Text(selection.isEmpty ? "Pick servers to stop" : "freed by stopping \(selectedServers.count)")
                        .font(Theme.body)
                        .foregroundStyle(Theme.text2)
                } else {
                    Text("CPU \(Format.percent(monitor.totalCPU))")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.text3)
                }
            }
            MemoryShareBar(servers: visibleServers, monitor: monitor, focusedPort: $focusedPort,
                           selection: isCleaning ? selection : nil) { server in
                if isCleaning { toggle(server.port) } else { openServer(server) }
            }
            .frame(height: 16)
        }
        .padding(EdgeInsets(top: 12, leading: Theme.inset, bottom: 16, trailing: Theme.inset))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(visibleServers) { server in
                ServerRow(server: server, monitor: monitor,
                          isFocused: focusedPort == server.port,
                          isDimmed: focusedPort != nil && focusedPort != server.port,
                          cleaning: isCleaning ? CleaningState(isSelected: selection.contains(server.port),
                                                               reason: monitor.cleanUpReason(for: server)) : nil,
                          open: { isCleaning ? toggle(server.port) : openServer(server) })
            }
        }
        .padding(6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DotGridView(glyph: .idle, size: 48)
            Text(monitor.hasScanned ? "Nothing listening" : "Scanning…")
                .font(Theme.body)
                .foregroundStyle(Theme.text2)
            Text("Dev servers on ports \(monitor.minPort)–\(monitor.maxPort) show up here.")
                .font(Theme.caption)
                .foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        if isCleaning {
            HStack(spacing: 8) {
                Button("Cancel") { setCleaning(false) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    for server in selectedServers { monitor.stop(server) }
                    setCleaning(false)
                } label: {
                    Text(selection.isEmpty
                         ? "Stop servers"
                         : "Stop \(selectedServers.count) \(selectedServers.count == 1 ? "server" : "servers") · free \(Format.bytesString(selectedServers.reduce(0) { $0 + $1.memory }))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(kind: .destructive))
                .disabled(selection.isEmpty)
                .opacity(selection.isEmpty ? 0.5 : 1)
            }
            .padding(12)
            .transition(.opacity)
        } else {
            HStack {
                Button { setCleaning(true) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 11, weight: .medium))
                        Text("Clean up")
                        let count = monitor.suggestedCleanUpCount
                        if count > 0 {
                            Text(String(count)).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                        }
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(monitor.servers.isEmpty)

                Spacer()

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")
            }
            .padding(12)
            .transition(.opacity)
        }
    }

    // MARK: - Clean up mode

    private func setCleaning(_ cleaning: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            selection = cleaning ? Self.suggestedSelection(monitor) : []
            isCleaning = cleaning
        }
    }

    private func toggle(_ port: Int) {
        withAnimation(.snappy(duration: 0.15)) {
            if selection.contains(port) { selection.remove(port) } else { selection.insert(port) }
        }
    }

    /// Everything Clean up suggests, except leaking servers, which are usually still in use.
    private static func suggestedSelection(_ monitor: ServerMonitor) -> Set<Int> {
        Set(monitor.cleanUpCandidates.compactMap { candidate in
            if case .leaking = candidate.reason { return nil }
            return candidate.server.port
        })
    }
}

// MARK: - Row

struct CleaningState {
    let isSelected: Bool
    let reason: CleanUpReason?
}

struct ServerRow: View {
    let server: Server
    @ObservedObject var monitor: ServerMonitor
    var isFocused = false
    var isDimmed = false
    /// Non-nil while the page is in Clean up mode.
    var cleaning: CleaningState?
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        let status = monitor.status(of: server)
        let attention = status == .attention
        HStack(spacing: 0) {
            if let cleaning {
                Checkbox(isOn: cleaning.isSelected)
                    .padding(.trailing, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            PortLabel(port: server.port, status: status)
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.project.name)
                    .font(Theme.bodyMedium)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .help(server.project.name)
                if let reason = cleaning?.reason {
                    HStack(spacing: 5) {
                        Image(systemName: reason.symbol).font(.system(size: 9, weight: .medium))
                        Text(reason.label).lineLimit(1)
                    }
                    .font(Theme.caption)
                    .foregroundStyle(reason.isLeak ? Theme.amber : Theme.text2)
                } else {
                    context(status: status)
                }
            }
            .padding(.trailing, 10)

            Spacer(minLength: 0)

            Group {
                if isHovered && cleaning == nil {
                    HStack(spacing: 2) {
                        IconButton(systemName: "arrow.up.right", size: 22, help: "Open in browser") {
                            NSWorkspace.shared.open(server.url)
                        }
                        IconButton(systemName: "stop.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 22, help: "Stop") {
                            monitor.stop(server)
                        }
                    }
                } else {
                    Sparkline(values: server.history.map { Double($0.memory) },
                              color: attention ? Theme.amber : Theme.text1.opacity(0.7),
                              lineWidth: attention ? 1.5 : 1.25)
                }
            }
            .frame(width: 40, height: 18)

            Text(Format.bytesString(server.memory))
                .font(Theme.mono)
                .foregroundStyle(attention ? Theme.amber : Theme.text1.opacity(0.85))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(isDimmed ? 0.35 : (status == .idle && !server.cwdExists ? 0.55 : 1))
        .hoverHighlight(isHovered || isFocused)
        .animation(.easeOut(duration: 0.12), value: isDimmed)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: open)
    }

    @ViewBuilder private func context(status: ServerStatus) -> some View {
        if status == .attention, server.isLeaking() {
            Text("+\(Format.bytesString(UInt64(server.memoryGrowth))) in \(Format.duration(historySpan))")
                .font(Theme.caption)
                .foregroundStyle(Theme.amber)
        } else if status == .attention {
            Text("Over \(MemoryChart.trim(Double(monitor.alertThreshold) / 1_000_000_000)) GB")
                .font(Theme.caption)
                .foregroundStyle(Theme.amber)
        } else {
            HStack(spacing: 5) {
                if let agent = server.agent { AgentGlyph(kind: agent.kind, size: 10) }
                if server.cwdExists, let branch = server.project.branch {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 8, weight: .medium))
                    HStack(spacing: 3) {
                        Text(branch).lineLimit(1).truncationMode(.tail).help(branch)
                        Text("· " + contextText).fixedSize()
                    }
                } else {
                    Text(contextText).lineLimit(1)
                }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.text2)
        }
    }

    /// Uptime or idle time, prefixed with the location when there's no branch.
    private var contextText: String {
        if !server.cwdExists { return "Worktree deleted · idle \(Format.shortDuration(server.idleFor))" }
        let time = server.idleFor > 60 * 60
            ? "idle \(Format.shortDuration(server.idleFor))"
            : server.uptime.map { "up \(Format.shortDuration($0))" } ?? ""
        if server.project.branch != nil { return time }
        return [server.locationLabel, time].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var historySpan: TimeInterval {
        guard let first = server.history.first, let last = server.history.last else { return 0 }
        return last.time.timeIntervalSince(first.time)
    }
}

struct Checkbox: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(isOn ? Theme.text1 : Color.white.opacity(0.06))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.ink)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.text3, lineWidth: 1)
                }
            }
            .frame(width: 16, height: 16)
    }
}

extension CleanUpReason {
    var isLeak: Bool {
        if case .leaking = self { return true }
        return false
    }

    var symbol: String {
        switch self {
        case .worktreeDeleted: return "folder.badge.minus"
        case .idle: return "clock"
        case .longRunning: return "calendar"
        case .leaking: return "chart.line.uptrend.xyaxis"
        }
    }

    var label: String {
        switch self {
        case .worktreeDeleted: return "Worktree deleted"
        case .idle(let duration): return "Idle \(Format.shortDuration(duration)) · no connections"
        case .longRunning(let duration): return "Running for \(Format.shortDuration(duration))"
        case .leaking(let growth): return "Leaking · +\(Format.bytesString(growth))"
        }
    }
}

// MARK: - Memory share bar

struct MemoryShareBar: View {
    let servers: [Server]
    @ObservedObject var monitor: ServerMonitor
    @Binding var focusedPort: Int?
    /// In Clean up mode, selected servers stay bright and the rest dim.
    var selection: Set<Int>?
    let activate: (Server) -> Void

    var body: some View {
        GeometryReader { geometry in
            let total = max(servers.reduce(0) { $0 + $1.memory }, 1)
            let spacing: CGFloat = 2
            let available = geometry.size.width - spacing * CGFloat(max(servers.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(Array(servers.enumerated()), id: \.element.id) { index, server in
                    let isFocused = focusedPort == server.port
                    let isSelected = selection?.contains(server.port) ?? false
                    let isDimmed = (focusedPort != nil && !isFocused) || (selection != nil && !isSelected && !isFocused)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color(for: server, index: index, highlighted: isFocused || isSelected))
                        .frame(height: isFocused ? 8 : 6)
                        .opacity(isDimmed ? 0.35 : 1)
                        // A tall, invisible hit area so thin segments are easy to hover.
                        .frame(width: max(available * CGFloat(server.memory) / CGFloat(total), 2), height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { focusedPort = server.port } else if focusedPort == server.port { focusedPort = nil }
                        }
                        .onTapGesture {
                            if selection == nil { focusedPort = nil }
                            activate(server)
                        }
                        .help("\(server.project.name) :\(String(server.port)) · \(Format.bytesString(server.memory))")
                }
            }
            .animation(.easeOut(duration: 0.12), value: focusedPort)
        }
    }

    private func color(for server: Server, index: Int, highlighted: Bool) -> Color {
        if monitor.status(of: server) == .attention { return Theme.amber }
        if highlighted { return Theme.text1.opacity(0.95) }
        let opacities: [Double] = [0.82, 0.55, 0.4, 0.3, 0.22]
        return Theme.text1.opacity(opacities[min(index, opacities.count - 1)])
    }
}
