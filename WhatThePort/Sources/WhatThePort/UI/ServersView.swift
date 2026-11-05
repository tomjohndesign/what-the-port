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
    /// Clean up and Pause multiple are modes of this page: checkboxes slide in
    /// and the footer turns into Cancel / Stop or Pause.
    private enum SelectionMode { case cleanUp, pause }
    @State private var mode: SelectionMode?
    private var isCleaning: Bool { mode == .cleanUp }
    @AppStorage(Preferences.serverSort) private var sort = ServerSort.port
    /// Rows hold still under the pointer, so a re-sort can't move Stop onto another server.
    @State private var heldOrder: [Int]?
    @State private var selection: Set<Int> = []

    init(monitor: ServerMonitor, startCleaning: Bool = false, openServer: @escaping (Server) -> Void, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openServer = openServer
        self.openSettings = openSettings
        _mode = State(initialValue: startCleaning ? .cleanUp : nil)
        _selection = State(initialValue: startCleaning ? Self.suggestedSelection(monitor) : [])
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            if visibleServers.isEmpty {
                SectionDivider()
            } else {
                SortDivider(sort: $sort)
            }
            if visibleServers.isEmpty {
                emptyState
            } else if rowsHeight > maxRowsHeight {
                ScrollView { rows }.frame(height: maxRowsHeight)
            } else {
                rows
            }
            SectionDivider()
            footer
        }
        .onChange(of: hoveredRow != nil || focus != nil) { _, holding in
            heldOrder = holding ? visibleServers.map(\.port) : nil
        }
    }

    private var maxRowsHeight: CGFloat { CGFloat(maxVisibleRows) * 52 + 12 }
    private var rowsHeight: CGFloat {
        CGFloat(visibleServers.count) * 52 + CGFloat(sections.filter { $0.title != nil }.count) * ServerSectionHeader.height + 12
    }

    /// Protected processes (databases) can't be stopped from Clean up or paused
    /// in bulk, so hide them there.
    private var sections: [ServerSection] {
        let servers: [Server]
        switch mode {
        case .cleanUp: servers = monitor.servers.filter { !$0.isProtected }
        case .pause: servers = pausableServers
        case nil: servers = monitor.servers
        }
        guard let heldOrder else { return ServerSection.arrange(sort.sorted(servers), sort: sort) }
        let held = servers.sorted { (heldOrder.firstIndex(of: $0.port) ?? .max) < (heldOrder.firstIndex(of: $1.port) ?? .max) }
        return ServerSection.arrange(held, sort: nil)
    }

    private var visibleServers: [Server] { sections.flatMap(\.servers) }

    private var pausableServers: [Server] {
        monitor.servers.filter { !$0.isProtected && !$0.isPaused }
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
                           selection: mode != nil ? selection : nil) { server in
                if mode != nil { toggle(server.port) } else { openServer(server) }
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
            PageHeader(title: monitor.server(port: port).map { "\($0.project.name) :\(String($0.port))" } ?? L10n.text("Servers"))
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
                Text(app?.name ?? L10n.text("App")).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        case .rest:
            HStack(spacing: 6) {
                Image(systemName: "macbook").font(.system(size: 12)).foregroundStyle(Theme.text2)
                Text(L10n.text("Everything else")).font(Theme.bodyMedium).foregroundStyle(Theme.text1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)
        case nil:
            PageHeader(title: L10n.text(mode == .cleanUp ? "Clean up" : mode == .pause ? "Pause multiple" : "Servers"))
        }
    }

    private var summaryAmount: (number: String, unit: String) {
        switch focus {
        case .server(let port): return Format.bytes(monitor.server(port: port)?.memory ?? 0)
        case .app(let id): return Format.bytes(monitor.otherApps.first { $0.id == id }?.memory ?? 0)
        case .rest: return Format.total(MemoryBreakdown(monitor: monitor).everythingElse)
        case nil:
            if mode != nil { return Format.total(ServerResources(selectedServers).memory) }
            return Format.total(monitor.totalMemory)
        }
    }

    @ViewBuilder private var summaryDetail: some View {
        let ram = monitor.systemMemory?.total ?? 0
        switch focus {
        case .server(let port):
            if let server = monitor.server(port: port) {
                Text(L10n.format("%@ of RAM · CPU %@", share(server.memory, of: ram), Format.percent(server.cpu)))
                    .font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .app(let id):
            if let app = monitor.otherApps.first(where: { $0.id == id }) {
                Text(L10n.format("%@ of RAM", share(app.memory, of: ram))).font(Theme.mono).foregroundStyle(Theme.text2)
            }
        case .rest:
            Text(L10n.text("System and smaller apps")).font(Theme.body).foregroundStyle(Theme.text2)
        case nil:
            if mode == .pause {
                if selectedServers.isEmpty {
                    Text(L10n.text("Pick servers to pause")).font(Theme.body).foregroundStyle(Theme.text2)
                } else {
                    let selected = ServerResources(selectedServers)
                    Text(L10n.format("%@ of RAM · CPU %@", share(selected.memory, of: ram), Format.percent(selected.cpu)))
                        .font(Theme.mono).foregroundStyle(Theme.text2)
                }
            } else if isCleaning {
                Text(selection.isEmpty ? L10n.text("Pick servers to stop") : L10n.format("freed by stopping %d", selectedServers.count))
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
            ForEach(sections) { section in
                if section.title != nil {
                    ServerSectionHeader(section: section, canStop: mode == nil) {
                        Usage.record(.stop)
                        monitor.stop(section.servers)
                    }
                }
                ForEach(section.servers) { server in
                    ServerRow(server: server, monitor: monitor,
                              isFocused: focusedPort == server.port,
                              isDimmed: focus != nil && focusedPort != server.port,
                              selecting: mode != nil ? RowSelection(isSelected: selection.contains(server.port),
                                                                    reason: isCleaning ? monitor.cleanUpReason(for: server) : nil) : nil,
                              onHover: { hovering in
                                  if hovering { hoveredRow = server.port } else if hoveredRow == server.port { hoveredRow = nil }
                              },
                              open: { mode != nil ? toggle(server.port) : openServer(server) })
                }
            }
        }
        .padding(6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            DotGridView(glyph: .idle, size: 48)
            Text(monitor.hasScanned ? L10n.text("Nothing listening") : L10n.text("Scanning…"))
                .font(Theme.body)
                .foregroundStyle(Theme.text2)
            Text(L10n.format("Dev servers on ports %d–%d show up here.", monitor.minPort, monitor.maxPort))
                .font(Theme.caption)
                .foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        if let mode {
            HStack(spacing: 8) {
                Button(L10n.text("Cancel")) { setMode(nil) }
                    .buttonStyle(PillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button {
                    switch mode {
                    case .cleanUp:
                        Usage.record(.cleanUp)
                        for server in selectedServers { monitor.stop(server) }
                    case .pause:
                        Usage.record(.pause)
                        monitor.pause(selectedServers)
                    }
                    setMode(nil)
                } label: {
                    Text(selectionActionLabel(mode)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(kind: mode == .cleanUp ? .destructive : .primary))
                .disabled(selectedServers.isEmpty)
                .opacity(selectedServers.isEmpty ? 0.5 : 1)
            }
            .padding(12)
            .transition(.opacity)
        } else {
            HStack(spacing: 8) {
                Button { setMode(.cleanUp) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 11, weight: .medium))
                        Text(L10n.text("Clean up"))
                        let count = monitor.suggestedCleanUpCount
                        if count > 0 {
                            Text(String(count)).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                        }
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(monitor.servers.isEmpty)

                Button { setMode(.pause) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .medium))
                        Text(L10n.text("Pause multiple"))
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(pausableServers.isEmpty)
                .opacity(pausableServers.isEmpty ? 0.5 : 1)

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
                .help(L10n.text("Settings"))
            }
            .padding(12)
            .transition(.opacity)
        }
    }

    // MARK: - Selection modes

    private func setMode(_ next: SelectionMode?) {
        withAnimation(.snappy(duration: 0.25)) {
            selection = next == .cleanUp ? Self.suggestedSelection(monitor) : []
            mode = next
        }
    }

    private func selectionActionLabel(_ mode: SelectionMode) -> String {
        let count = selectedServers.count
        let noun = L10n.counted("server", "servers", count: count)
        switch mode {
        case .cleanUp:
            return count == 0 ? L10n.text("Stop servers") : L10n.format("Stop %d %@ · free %@", count, noun, Format.bytesString(ServerResources(selectedServers).memory))
        case .pause:
            return count == 0 ? L10n.text("Pause servers") : L10n.format("Pause %d %@", count, noun)
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
                Text(showsAll ? L10n.text("CPU (all)") : L10n.text("CPU (servers)")).font(Theme.body).foregroundStyle(Theme.text3)
                Text(Format.percent(showsAll ? (monitor.systemCPU ?? 0) : monitor.serversShareOfCPU))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.text2)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(showsAll ? L10n.text("Whole Mac. Click for servers only.") : L10n.text("Dev servers, as a share of the whole Mac. Click for all."))
    }
}

/// The line above the rows, with the sort menu set into it in small text.
private struct SortDivider: View {
    @Binding var sort: ServerSort
    private let gap: CGFloat = 6

    var body: some View {
        HStack(spacing: gap) {
            SectionDivider()
            Menu {
                Picker(selection: $sort) {
                    ForEach(ServerSort.allCases) { option in
                        Text(option.label).tag(option)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 3) {
                    Text(sort.label).font(Theme.caption).foregroundStyle(Theme.text3)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.text3)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.text("Sort servers"))
            SectionDivider().frame(width: Theme.inset - gap)
        }
        // Takes up no more room than the plain divider it replaces.
        .frame(height: 14)
        .padding(.vertical, -7)
        .zIndex(1)
    }
}

extension ServerSort {
    var label: String {
        switch self {
        case .usage: return L10n.text("Usage")
        case .recency: return L10n.text("Recency")
        case .name: return L10n.text("Name")
        case .port: return L10n.text("Port")
        }
    }
}

// MARK: - Row

/// Names a group of containers, with its total memory lined up with the rows'.
private struct ServerSectionHeader: View {
    static let height: CGFloat = 28

    let section: ServerSection
    let canStop: Bool
    let stop: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(section.title ?? "")
                .font(Theme.captionMedium)
                .foregroundStyle(Theme.text1)
                .lineLimit(1)
            if let detail = section.detail {
                Text(detail)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            if isHovered && canStop {
                IconButton(systemName: "stop.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 18, help: L10n.text("Stop all"), action: stop)
            }
            Text(Format.bytesString(section.memory))
                .font(Theme.monoCaption)
                .foregroundStyle(Theme.text3)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height, alignment: .bottom)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct RowSelection {
    let isSelected: Bool
    let reason: CleanUpReason?
}

struct ServerRow: View {
    let server: Server
    @ObservedObject var monitor: ServerMonitor
    var isFocused = false
    var isDimmed = false
    /// Non-nil while the page is in Clean up or Pause multiple mode.
    var selecting: RowSelection?
    var onHover: (Bool) -> Void = { _ in }
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        let status = monitor.status(of: server)
        let attention = status == .attention
        HStack(spacing: 0) {
            if let selecting {
                Checkbox(isOn: selecting.isSelected)
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
                if let reason = selecting?.reason {
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
                if isHovered && selecting == nil {
                    HStack(spacing: 2) {
                        IconButton(systemName: "arrow.up.right", size: 22, help: L10n.text("Open in browser")) {
                            Usage.record(.openBrowser)
                            NSWorkspace.shared.open(server.url)
                        }
                        IconButton(systemName: server.isPaused ? "play.fill" : "pause.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 22, help: L10n.text(server.isPaused ? "Resume" : "Pause")) {
                            if !server.isPaused { Usage.record(.pause) }
                            monitor.togglePause(server)
                        }
                        IconButton(systemName: "stop.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 22, help: L10n.text("Stop")) {
                            Usage.record(.stop)
                            monitor.stop(server)
                        }
                    }
                } else {
                    Sparkline(values: server.history.map { Double($0.memory) },
                              color: attention ? Theme.amber : Theme.text1.opacity(0.7),
                              lineWidth: attention ? 1.5 : 1.25)
                }
            }
            .frame(width: isHovered && selecting == nil ? 70 : 40, height: 18)

            Text(Format.bytesString(server.memory))
                .font(Theme.mono)
                .foregroundStyle(attention ? Theme.amber : Theme.text1.opacity(0.85))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(isDimmed ? 0.35 : ((status == .idle && !server.cwdExists) || (status == .paused && !isHovered) ? 0.55 : 1))
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
            attentionText(L10n.format("+%@ in %@", Format.bytesString(UInt64(server.memoryGrowth)), L10n.duration(historySpan)))
        } else if status == .attention {
            attentionText(L10n.format("Over %@ GB", MemoryChart.trim(Double(monitor.alertThreshold) / Format.gigabyte)))
        } else {
            HStack(spacing: 5) {
                if let agent = server.agent { AgentGlyph(kind: agent.kind, size: 10) }
                if let container = server.container {
                    // Like native rows, only the image truncates; the time always shows.
                    ServiceGlyph(service: container.service)
                    HStack(spacing: 3) {
                        Text(container.shortImage)
                            .lineLimit(1).truncationMode(.tail).help(container.image)
                        if !contextText.isEmpty { Text("· " + contextText).fixedSize() }
                    }
                } else if server.cwdExists, server.project.branch != nil {
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

    /// A container keeps its icon, so you can still see what's leaking.
    private func attentionText(_ text: String) -> some View {
        HStack(spacing: 5) {
            if let container = server.container { ServiceGlyph(service: container.service, color: Theme.amber) }
            Text(text)
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.amber)
    }

    private var primaryName: String { server.listTitle }

    /// Uptime or idle time, prefixed with the location when there's no branch.
    private var contextText: String {
        if !server.cwdExists, !server.isPaused { return L10n.format("Worktree deleted · idle %@", L10n.duration(server.idleFor, short: true)) }
        let time = server.isPaused
            ? L10n.text("paused")
            : server.isIdle
                ? L10n.format("idle %@", L10n.duration(server.idleFor, short: true))
                : server.uptime.map { L10n.format("up %@", L10n.duration($0, short: true)) } ?? ""
        if server.project.branch != nil || server.container != nil { return time }
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
        case .worktreeDeleted: return L10n.text("Worktree deleted")
        case .idle(let duration): return L10n.format("Idle %@ · no connections", L10n.duration(duration, short: true))
        case .longRunning(let duration): return L10n.format("Running for %@", L10n.duration(duration, short: true))
        case .leaking(let growth): return L10n.format("Leaking · +%@", Format.bytesString(growth))
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
            let shares = ServerResources(servers).memoryByPort
            let segmentCount = servers.count + apps.count + (breakdown.everythingElse > 0 ? 1 : 0)
            let filled = breakdown.devServers + apps.reduce(0) { $0 + $1.memory } + breakdown.everythingElse
            let capacity = max(breakdown.total ?? filled, filled, 1)
            let unit = max(geometry.size.width - CGFloat(max(segmentCount - 1, 0)) * spacing, 0) / CGFloat(capacity)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.memoryTrack)
                    .frame(height: 4)
                    .help(L10n.format("Free · %@", Format.bytesString(breakdown.free)))
                HStack(spacing: spacing) {
                    ForEach(servers) { server in
                        serverSegment(server, width: max(unit * CGFloat(shares[server.port] ?? 0), 2), height: geometry.size.height)
                    }
                    ForEach(apps) { app in
                        baselineSegment(focus: .app(app.id), width: unit * CGFloat(app.memory), height: geometry.size.height,
                                        help: "\(app.name) · \(Format.bytesString(app.memory))")
                    }
                    if breakdown.everythingElse > 0 {
                        baselineSegment(focus: .rest, width: unit * CGFloat(breakdown.everythingElse), height: geometry.size.height,
                                        help: L10n.format("Everything else · %@", Format.bytesString(breakdown.everythingElse)))
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
            item(swatch: Theme.text1.opacity(0.95), label: L10n.text("Servers"), value: amount(breakdown.devServers))
            item(swatch: Theme.text1.opacity(0.12), label: L10n.text("Other apps"), value: amount(breakdown.otherApps))
            if let total = breakdown.total {
                item(swatch: Theme.memoryTrack, label: L10n.text("Free"), value: L10n.format("%@ of %@", Format.total(breakdown.free).number, amount(total)))
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
            RoundedRectangle(cornerRadius: 1.5).fill(swatch).frame(width: 8, height: label == L10n.text("Servers") ? 8 : 4)
            Text(label).font(Theme.caption).foregroundStyle(Theme.text2)
            Text(value).font(Theme.monoCaption).foregroundStyle(Theme.text3)
        }
        .fixedSize()
    }
}
