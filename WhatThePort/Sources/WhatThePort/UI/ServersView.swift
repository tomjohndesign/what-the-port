import SwiftUI

struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openServer: (Server) -> Void
    let openSettings: () -> Void

    private let maxVisibleRows = 7
    /// The memory-bar segment under the pointer.
    @State private var focus: BarFocus?
    /// Row under the pointer; lights up its bar segment without changing the header.
    @State private var hoveredRow: Int?
    private var focusedPort: Int? { if case .server(let port) = focus { return port } else { return nil } }
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
        VStack(alignment: .leading, spacing: 10) {
            summaryTitle
            HStack(alignment: .center) {
                let amount = summaryAmount
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(amount.number).font(Theme.display).foregroundStyle(Theme.text1)
                        .contentTransition(.numericText())
                    Text(amount.unit).font(Theme.mono).foregroundStyle(Theme.text3)
                }
                Spacer()
                summaryDetail
            }
            MemoryShareBar(servers: visibleServers, monitor: monitor, focus: $focus, highlightedPort: hoveredRow,
                           selection: isCleaning ? selection : nil) { server in
                if isCleaning { toggle(server.port) } else { openServer(server) }
            }
            .frame(height: 16)
            MemoryLegend(monitor: monitor)
        }
        .padding(EdgeInsets(top: 12, leading: Theme.inset, bottom: 16, trailing: Theme.inset))
    }

    /// Title row: the page name, or whatever bar segment is under the pointer.
    @ViewBuilder private var summaryTitle: some View {
        switch focus {
        case .server(let port):
            PageHeader(title: monitor.server(port: port).map { "\($0.project.name) :\(String($0.port))" } ?? "Servers")
        case .app(let id):
            let app = monitor.otherApps.first { $0.id == id }
            HStack(spacing: 6) {
                if let path = app?.bundlePath {
                    Image(nsImage: AppIcons.icon(for: path)).resizable().frame(width: 16, height: 16)
                } else if let agent = app?.agent {
                    AgentGlyph(kind: agent, size: 12, color: Theme.text1)
                } else {
                    Image(systemName: "terminal").font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
                Text(app?.name ?? "App").font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        case .rest:
            HStack(spacing: 6) {
                Image(systemName: "macbook").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text("Everything else").font(Theme.bodyMedium).foregroundStyle(Theme.text1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        case nil:
            PageHeader(title: isCleaning ? "Clean up" : "Servers")
        }
    }

    private var summaryAmount: (number: String, unit: String) {
        switch focus {
        case .server(let port): return Format.bytes(monitor.server(port: port)?.memory ?? 0)
        case .app(let id): return Format.bytes(monitor.otherApps.first { $0.id == id }?.memory ?? 0)
        case .rest: return Format.total(MemoryBreakdown(monitor: monitor).everythingElse)
        case nil:
            if isCleaning { return Format.total(selectedServers.reduce(0) { $0 + $1.memory }) }
            return Format.total(monitor.totalMemory)
        }
    }

    @ViewBuilder private var summaryDetail: some View {
        let ram = monitor.systemMemory?.total ?? 0
        switch focus {
        case .server(let port):
            if let server = monitor.server(port: port) {
                Text("\(share(server.memory, of: ram)) of RAM · CPU \(Format.percent(server.cpu))")
                    .font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .app(let id):
            if let app = monitor.otherApps.first(where: { $0.id == id }) {
                Text("\(share(app.memory, of: ram)) of RAM").font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .rest:
            Text("System and smaller apps").font(Theme.body).foregroundStyle(Theme.text2)
        case nil:
            if isCleaning {
                Text(selection.isEmpty ? "Pick servers to stop" : "freed by stopping \(selectedServers.count)")
                    .font(Theme.body).foregroundStyle(Theme.text2)
            } else {
                CPUToggle(monitor: monitor)
            }
        }
    }

    private func share(_ bytes: UInt64, of total: UInt64) -> String {
        Format.percent(Double(bytes) / Double(max(total, 1)) * 100)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(visibleServers) { server in
                ServerRow(server: server, monitor: monitor,
                          isFocused: focusedPort == server.port,
                          isDimmed: focus != nil && focusedPort != server.port,
                          cleaning: isCleaning ? CleaningState(isSelected: selection.contains(server.port),
                                                               reason: monitor.cleanUpReason(for: server)) : nil,
                          onHover: { hovering in
                              if hovering { hoveredRow = server.port } else if hoveredRow == server.port { hoveredRow = nil }
                          },
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

/// One CPU reading at a time; click to switch between servers and the whole Mac.
private struct CPUToggle: View {
    @ObservedObject var monitor: ServerMonitor
    @AppStorage("servers.cpuShowsAll") private var showsAll = false

    var body: some View {
        Button {
            showsAll.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(showsAll ? "CPU (all)" : "CPU (servers)").font(Theme.body).foregroundStyle(Theme.text3)
                Text(Format.percent(showsAll ? (monitor.systemCPU ?? 0) : monitor.serversShareOfCPU))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text2)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsAll ? "Whole Mac. Click for servers only." : "Dev servers, as a share of the whole Mac. Click for all.")
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
    var onHover: (Bool) -> Void = { _ in }
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

            PortLabel(port: server.port, status: status, color: Theme.portColor(at: monitor.colorIndex(for: server.port)))
                .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryName.replacingOccurrences(of: "-", with: " "))
                    .font(Theme.bodyMedium)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .help(primaryName)
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
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
        .onTapGesture(perform: open)
    }

    @ViewBuilder private func context(status: ServerStatus) -> some View {
        if status == .attention, server.isLeaking() {
            Text("+\(Format.bytesString(UInt64(server.memoryGrowth))) in \(Format.duration(historySpan))")
                .font(Theme.caption)
                .foregroundStyle(Theme.amber)
        } else if status == .attention {
            Text("Over \(MemoryChart.trim(Double(monitor.alertThreshold) / Format.gigabyte)) GB")
                .font(Theme.caption)
                .foregroundStyle(Theme.amber)
        } else {
            HStack(spacing: 5) {
                if let agent = server.agent { AgentGlyph(kind: agent.kind, size: 10) }
                if server.cwdExists, server.project.branch != nil {
                    HStack(spacing: 3) {
                        Text(server.project.name.replacingOccurrences(of: "-", with: " "))
                            .lineLimit(1).truncationMode(.tail).help(server.project.name)
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

    private var primaryName: String {
        server.project.branch ?? server.project.name
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
            .fill(isOn ? Theme.text1 : Theme.fill)
            .overlay {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onPrimary)
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

// MARK: - Memory bar

enum BarFocus: Equatable {
    case server(Int)
    case app(String)
    case rest
}

/// The Mac's whole memory: each dev server as a raised segment, then the
/// biggest other apps and "everything else" as a thin baseline, with free
/// memory as the empty track. Every segment is hoverable.
struct MemoryShareBar: View {
    let servers: [Server]
    @ObservedObject var monitor: ServerMonitor
    @Binding var focus: BarFocus?
    /// A server whose row is hovered in the list.
    var highlightedPort: Int?
    /// In Clean up mode, selected servers stay bright and the rest dim.
    var selection: Set<Int>?
    let activate: (Server) -> Void

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let breakdown = MemoryBreakdown(monitor: monitor)
            let apps = breakdown.topApps
            let segmentCount = servers.count + apps.count + (breakdown.everythingElse > 0 ? 1 : 0)
            let filled = breakdown.devServers + apps.reduce(0) { $0 + $1.memory } + breakdown.everythingElse
            let capacity = max(breakdown.total ?? filled, filled, 1)
            let unit = max(geometry.size.width - CGFloat(max(segmentCount - 1, 0)) * spacing, 0) / CGFloat(capacity)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.memoryTrack)
                    .frame(height: 4)
                    .help("Free · \(Format.bytesString(breakdown.free))")
                HStack(spacing: spacing) {
                    ForEach(servers) { server in
                        serverSegment(server, width: max(unit * CGFloat(server.memory), 2), height: geometry.size.height)
                    }
                    ForEach(apps) { app in
                        baselineSegment(focus: .app(app.id), width: unit * CGFloat(app.memory), height: geometry.size.height,
                                        help: "\(app.name) · \(Format.bytesString(app.memory))")
                    }
                    if breakdown.everythingElse > 0 {
                        baselineSegment(focus: .rest, width: unit * CGFloat(breakdown.everythingElse), height: geometry.size.height,
                                        help: "Everything else · \(Format.bytesString(breakdown.everythingElse))")
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.12), value: focus)
            .animation(.easeOut(duration: 0.12), value: highlightedPort)
        }
    }

    private func serverSegment(_ server: Server, width: CGFloat, height: CGFloat) -> some View {
        let isFocused = focus == .server(server.port) || (focus == nil && highlightedPort == server.port)
        let isSelected = selection?.contains(server.port) ?? false
        let someoneFocused = focus != nil || highlightedPort != nil
        let isDimmed = (someoneFocused && !isFocused) || (selection != nil && !isSelected && !isFocused)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(Theme.portColor(at: monitor.colorIndex(for: server.port)))
            .frame(height: isFocused ? 10 : 8)
            .opacity(isDimmed ? 0.35 : 1)
            // A tall, invisible hit area so thin segments are easy to hover.
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onHover { hovering in setFocus(.server(server.port), hovering) }
            .onTapGesture {
                if selection == nil { focus = nil }
                activate(server)
            }
            .help("\(server.project.name) :\(String(server.port)) · \(Format.bytesString(server.memory))")
    }

    /// Other apps sit on the thin baseline; hovering one lifts and brightens it.
    private func baselineSegment(focus target: BarFocus, width: CGFloat, height: CGFloat, help: String) -> some View {
        let isFocused = focus == target
        return RoundedRectangle(cornerRadius: 1)
            .fill(Theme.text1.opacity(isFocused ? 0.7 : 0.12))
            .frame(height: isFocused ? 8 : 4)
            .opacity((focus != nil || highlightedPort != nil) && !isFocused ? 0.6 : 1)
            .frame(width: max(width, 1), height: height)
            .contentShape(Rectangle())
            .onHover { hovering in setFocus(target, hovering) }
            .help(help)
    }

    private func setFocus(_ target: BarFocus, _ hovering: Bool) {
        if hovering { focus = target } else if focus == target { focus = nil }
    }

}

struct MemoryBreakdown {
    let devServers: UInt64
    let otherApps: UInt64
    let free: UInt64
    let total: UInt64?
    /// Apps big enough to get their own segment (≥2% of RAM, at most eight).
    let topApps: [AppMemory]
    /// Used memory not covered by dev servers or top apps: system and small apps.
    let everythingElse: UInt64

    @MainActor
    init(monitor: ServerMonitor) {
        devServers = monitor.totalMemory
        let used = monitor.systemMemory?.used ?? devServers
        otherApps = used > devServers ? used - devServers : 0
        free = monitor.systemMemory?.free ?? 0
        total = monitor.systemMemory?.total
        let minimum = UInt64(Double(total ?? 0) * 0.02)
        var budget = otherApps
        var picked: [AppMemory] = []
        for app in monitor.otherApps.prefix(8) where app.memory >= minimum && app.memory <= budget {
            picked.append(app)
            budget -= app.memory
        }
        topApps = picked
        everythingElse = budget
    }
}

/// Servers · Other apps · Free of the Mac's total.
struct MemoryLegend: View {
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        let breakdown = MemoryBreakdown(monitor: monitor)
        HStack(spacing: 10) {
            item(swatch: Theme.text1.opacity(0.95), label: "Servers", value: amount(breakdown.devServers))
            item(swatch: Theme.text1.opacity(0.12), label: "Other apps", value: amount(breakdown.otherApps))
            if let total = breakdown.total {
                item(swatch: Theme.memoryTrack, label: "Free", value: "\(Format.total(breakdown.free).number) of \(amount(total))")
            }
            Spacer(minLength: 0)
        }
    }

    private func amount(_ bytes: UInt64) -> String {
        let value = Format.total(bytes)
        return "\(value.number) \(value.unit)"
    }

    private func item(swatch: Color, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5).fill(swatch).frame(width: 8, height: label == "Servers" ? 8 : 4)
            Text(label).font(Theme.caption).foregroundStyle(Theme.text2)
            Text(value).font(Theme.monoCaption).foregroundStyle(Theme.text3)
        }
        .fixedSize()
    }
}
