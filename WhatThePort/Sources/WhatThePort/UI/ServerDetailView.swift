import Charts
import SwiftUI

struct ServerDetailView: View {
    let server: Server
    @ObservedObject var monitor: ServerMonitor
    @ObservedObject var github: GitHubLookup
    let back: () -> Void

    init(server: Server, monitor: ServerMonitor, back: @escaping () -> Void) {
        self.server = server
        self.monitor = monitor
        self.github = monitor.github
        self.back = back
    }

    @AppStorage("detail.infoExpanded") private var infoExpanded = false
    @AppStorage("detail.processesExpanded") private var processesExpanded = false
    /// Shared between both charts so hovering one scrubs the other.
    @State private var hoverTime: Date?

    var body: some View {
        let status = monitor.status(of: server)
        VStack(spacing: 0) {
            header(status: status)
            SectionDivider()
            infoList
            SectionDivider()
            charts
            SectionDivider()
            processes
            SectionDivider()
            footer
        }
        .onAppear { github.refresh(server, maxAge: 30) }
    }

    // MARK: - Header

    private func header(status: ServerStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: server.project.name, back: back)
            HStack {
                PortLabel(port: server.port, status: status, color: Theme.portColor(at: monitor.colorIndex(for: server.port)), large: true)
                Spacer()
                HStack(spacing: 10) {
                    if let uptime = server.uptime {
                        Text(L10n.format("Running for %@", L10n.duration(uptime))).font(Theme.body).foregroundStyle(Theme.text3)
                    }
                    HStack(spacing: 6) {
                        IconButton(systemName: "arrow.clockwise", help: restartHelp) {
                            Usage.record(.restart)
                            monitor.restart(server)
                        }
                        .disabled(server.launch == nil || !server.cwdExists)
                        IconButton(systemName: "stop.fill", tint: Theme.softRed, background: Theme.red.opacity(0.14), help: L10n.format("Stop %d processes", server.processes.count)) {
                            Usage.record(.stop)
                            monitor.stop(server)
                            back()
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: Theme.inset, bottom: 16, trailing: Theme.inset))
    }

    private var restartHelp: String {
        if let agent = server.agent {
            return L10n.format("Restart. It will run outside the %@ session.", agent.kind.rawValue)
        }
        return L10n.text("Restart with the same command")
    }

    // MARK: - Info

    private var infoList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let primary = primaryRows
            let secondary = secondaryRows
            ForEach(Array(primary.enumerated()), id: \.offset) { _, row in row }
            if infoExpanded {
                ForEach(Array(secondary.enumerated()), id: \.offset) { _, row in row }
            }
            if !secondary.isEmpty {
                HStack(spacing: 12) {
                    Spacer().frame(width: 64)
                    Disclosure(title: infoExpanded ? L10n.text("Less") : L10n.format("%d more", secondary.count), expanded: infoExpanded) {
                        withAnimation(.snappy(duration: 0.2)) { infoExpanded.toggle() }
                    }
                }
                .frame(height: 30)
            }
        }
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, 6)
    }

    private var primaryRows: [InfoRow] {
        var rows: [InfoRow] = []
        if let agent = server.agent {
            rows.append(InfoRow(label: L10n.text("Session"), tooltip: agent.title) { SessionValue(session: agent, server: server) })
        }
        if let branch = server.project.branch {
            rows.append(InfoRow(label: L10n.text("Branch"), tooltip: branch) { Text(branch).font(Theme.body).foregroundStyle(Theme.text1) })
        }
        if rows.count < 2, let folder = folderText {
            rows.append(InfoRow(label: L10n.text("Folder"), tooltip: server.cwd) { Text(folder).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        return rows
    }

    private var secondaryRows: [InfoRow] {
        var rows: [InfoRow] = []
        if let workspace = server.conductorWorkspace {
            rows.append(InfoRow(label: L10n.text("Workspace"), tooltip: "Conductor · \(workspace)") { Text("Conductor · \(workspace)").font(Theme.body).foregroundStyle(Theme.text2) })
        }
        if server.agent != nil || server.project.branch != nil, let folder = folderText {
            rows.append(InfoRow(label: L10n.text("Folder"), tooltip: server.cwd) { Text(folder).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let framework = server.project.framework {
            rows.append(InfoRow(label: L10n.text("Framework"), tooltip: framework) { Text(framework).font(Theme.body).foregroundStyle(Theme.text2) })
        }
        if let command = server.command {
            rows.append(InfoRow(label: L10n.text("Command"), tooltip: command) { Text(command).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let started = server.startedAt {
            rows.append(InfoRow(label: L10n.text("Started")) { Text(L10n.time(started)).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if let pr = github.result(for: server)?.pullRequest {
            rows.append(InfoRow(label: L10n.text("Pull request"), tooltip: "#\(pr.number) \(pr.title)") {
                Link(destination: pr.url) {
                    HStack(spacing: 6) {
                        Text("#\(pr.number)").font(Theme.mono).foregroundStyle(Theme.text1)
                        Text(pr.title).font(Theme.body).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                        Text(L10n.text(pr.state)).font(Theme.caption).foregroundStyle(Theme.text3).fixedSize()
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { Usage.record(.pullRequest) })
            })
        }
        if let agent = server.agent {
            rows.append(InfoRow(label: L10n.text("Session ID"), tooltip: agent.id) { Text(agent.id).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        if !server.addresses.isEmpty {
            rows.append(InfoRow(label: L10n.text("Address"), tooltip: server.addresses.joined(separator: " · ")) { Text(server.addresses.joined(separator: " · ")).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
        return rows
    }

    private var folderText: String? {
        guard let path = server.cwd else { return nil }
        let abbreviated = (path as NSString).abbreviatingWithTildeInPath
        let parts = abbreviated.split(separator: "/")
        guard parts.count > 3 else { return abbreviated }
        return "\(parts.first!)/…/" + parts.suffix(2).joined(separator: "/")
    }

    // MARK: - Charts

    private var charts: some View {
        VStack(alignment: .leading, spacing: 14) {
            MemoryChart(server: server, threshold: monitor.alertThreshold, hoverTime: $hoverTime)
            CPUChart(server: server, hoverTime: $hoverTime)
        }
        .padding(EdgeInsets(top: 12, leading: Theme.inset, bottom: 16, trailing: Theme.inset))
    }

    // MARK: - Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { processesExpanded.toggle() }
            } label: {
                HStack {
                    HStack(spacing: 4) {
                        Text(L10n.text("Processes")).font(Theme.body).foregroundStyle(Theme.text2)
                        Image(systemName: processesExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Text("\(server.processes.count) · \(Format.bytesString(server.memory))")
                        .font(Theme.mono)
                        .foregroundStyle(Theme.text2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if processesExpanded {
                let largest = max(server.processes.map(\.memory).max() ?? 1, 1)
                VStack(spacing: 5) {
                    ForEach(server.processes) { process in
                        HStack(spacing: 0) {
                            Text((process.depth > 0 ? String(repeating: "  ", count: process.depth - 1) + "└ " : "") + process.name)
                                .font(Theme.mono)
                                .foregroundStyle(process.pid == server.pid ? Theme.text1 : Theme.text1.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(process.name)
                            Spacer(minLength: 8)
                            Text(String(process.pid)).font(Theme.monoCaption).foregroundStyle(Theme.text3)
                                .frame(width: 52, alignment: .leading)
                            Capsule().fill(Theme.fill).frame(width: 64, height: 4)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.text1.opacity(process.pid == server.pid ? 0.75 : 0.45))
                                        .frame(width: max(64 * CGFloat(process.memory) / CGFloat(largest), 3), height: 4)
                                }
                            Text(Format.bytesString(process.memory))
                                .font(Theme.mono)
                                .foregroundStyle(Theme.text1.opacity(0.85))
                                .frame(width: 70, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 14, leading: Theme.inset, bottom: 14, trailing: Theme.inset))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Usage.record(.openBrowser)
                NSWorkspace.shared.open(server.url)
            } label: {
                Text(L10n.format("Open localhost:%@", String(server.port))).frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)

            if let preview = github.result(for: server)?.preview {
                Button {
                    Usage.record(.vercelPreview)
                    NSWorkspace.shared.open(preview.url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "triangle.fill").font(.system(size: 9))
                        Text(preview.state == .building ? L10n.text("Building") : L10n.text("Preview"))
                    }
                    .foregroundStyle(preview.state == .failed ? Theme.softRed : Theme.text1)
                }
                .buttonStyle(PillButtonStyle())
                .help(preview.state == .failed ? L10n.format("Preview build failed · %@", preview.url.host ?? "") : preview.url.absoluteString)
            }

            Menu {
                Button(L10n.text("Copy URL")) { copy(server.url.absoluteString) }
                if let command = server.command { Button(L10n.text("Copy command")) { copy(command) } }
                Divider()
                if let root = server.project.root ?? server.cwd, server.cwdExists {
                    Button(L10n.text("Open in editor")) {
                        Usage.record(.openEditor)
                        EditorLauncher.open(root)
                    }
                    Button(L10n.text("Reveal in Finder")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text1)
                    .frame(width: 30, height: 30)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Info rows

struct InfoRow: View {
    let label: String
    let tooltip: String?
    let value: AnyView

    /// `tooltip` shows the full value on hover, for anything that can truncate.
    init<V: View>(label: String, tooltip: String? = nil, @ViewBuilder value: () -> V) {
        self.label = label
        self.tooltip = tooltip
        self.value = AnyView(value())
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Theme.caption).foregroundStyle(Theme.text3).frame(width: 64, alignment: .leading)
            value.lineLimit(1).truncationMode(.middle)
                .help(tooltip ?? "")
            Spacer(minLength: 0)
        }
        .frame(height: 30)
    }
}

struct SessionValue: View {
    let session: AgentSession
    let server: Server

    var body: some View {
        Menu {
            Section("\(session.kind.rawValue)\(session.startedAt.map { L10n.format(" · started %@", L10n.time($0)) } ?? "")") {
                if let workspace = server.conductorWorkspace {
                    Button(L10n.format("Reveal %@ workspace", workspace)) { reveal(server.project.root ?? server.cwd) }
                }
                Button(L10n.format("Resume in %@", TerminalLauncher.current.name)) {
                    Usage.record(.resumeSession)
                    SessionLauncher.resume(session, fallbackDirectory: server.cwd)
                }
                if let transcript = session.transcript {
                    Button(L10n.text("Show transcript")) { NSWorkspace.shared.selectFile(transcript.path, inFileViewerRootedAtPath: "") }
                }
                Divider()
                Button(L10n.text("Copy session ID")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            }
        } label: {
            HStack(spacing: 6) {
                AgentGlyph(kind: session.kind)
                Text(session.title ?? session.kind.rawValue)
                    .font(Theme.body)
                    .foregroundStyle(Theme.text1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text2)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func reveal(_ path: String?) {
        guard let path else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}

// MARK: - Charts

struct MemoryChart: View {
    let server: Server
    let threshold: UInt64
    @Binding var hoverTime: Date?

    var body: some View {
        let values = server.history.map { (time: $0.time, gb: Double($0.memory) / Format.gigabyte) }
        let top = max(Double(threshold) / Format.gigabyte, (values.map(\.gb).max() ?? 0) * 1.1)
        let thresholdGB = Double(threshold) / Format.gigabyte
        let hovered = ChartHover.sample(in: server.history, near: hoverTime)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.text("Memory")).font(Theme.body).foregroundStyle(Theme.text2)
                Text(Format.bytesString(hovered?.memory ?? server.memory)).font(Theme.monoMedium).foregroundStyle(Theme.text1)
                Spacer()
                Text(hovered.map { ChartHover.timestamp($0.time) } ?? L10n.text("10 min"))
                    .font(Theme.monoCaption)
                    .foregroundStyle(hovered == nil ? Theme.text3 : Theme.text2)
            }
            Chart {
                RuleMark(y: .value(L10n.text("Alert"), thresholdGB))
                    .foregroundStyle(Theme.amber.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    LineMark(x: .value(L10n.text("Time"), value.time), y: .value("GB", value.gb))
                        .foregroundStyle(Theme.text1.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
                if let hovered {
                    RuleMark(x: .value(L10n.text("Time"), hovered.time))
                        .foregroundStyle(Theme.text1.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value(L10n.text("Time"), hovered.time), y: .value("GB", Double(hovered.memory) / Format.gigabyte))
                        .foregroundStyle(Theme.text1)
                        .symbolSize(30)
                } else if let last = values.last {
                    PointMark(x: .value(L10n.text("Time"), last.time), y: .value("GB", last.gb))
                        .foregroundStyle(Theme.text1)
                        .symbolSize(24)
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-ScanEngine.historyWindow)...Date())
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, thresholdGB]) { value in
                    AxisValueLabel {
                        if let gb = value.as(Double.self) {
                            Text(gb == 0 ? "0" : "\(Self.trim(gb)) GB")
                                .font(Theme.monoCaption)
                                .foregroundStyle(gb == 0 ? Theme.text3 : Theme.amber.opacity(0.85))
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.overlay(alignment: .leading) { Rectangle().fill(Theme.text1.opacity(0.14)).frame(width: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.text1.opacity(0.14)).frame(height: 1) }
            }
            .chartOverlay { proxy in ChartHover.overlay(proxy: proxy, hoverTime: $hoverTime) }
            .frame(height: ChartHover.height)
        }
    }

    static func trim(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct CPUChart: View {
    let server: Server
    @Binding var hoverTime: Date?

    var body: some View {
        let samples = server.history
        let hovered = ChartHover.sample(in: samples, near: hoverTime)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("CPU").font(Theme.body).foregroundStyle(Theme.text2)
                Text(Format.percent(hovered?.cpu ?? server.cpu)).font(Theme.monoMedium).foregroundStyle(Theme.text1)
                Spacer()
                if let hovered {
                    Text(ChartHover.timestamp(hovered.time)).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                }
            }
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    let isHighlighted = hovered.map { $0.time == sample.time } ?? (index == samples.count - 1)
                    BarMark(x: .value(L10n.text("Time"), sample.time, unit: .second), y: .value("CPU", min(sample.cpu, 100)), width: .fixed(3))
                        .foregroundStyle(Theme.text1.opacity(isHighlighted ? 0.85 : 0.32))
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                }
                if let hovered {
                    RuleMark(x: .value(L10n.text("Time"), hovered.time, unit: .second))
                        .foregroundStyle(Theme.text1.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: Date().addingTimeInterval(-ScanEngine.historyWindow)...Date())
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 100]) { value in
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text(percent == 0 ? "0" : "100%").font(Theme.monoCaption).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.overlay(alignment: .leading) { Rectangle().fill(Theme.text1.opacity(0.14)).frame(width: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.text1.opacity(0.14)).frame(height: 1) }
            }
            .chartOverlay { proxy in ChartHover.overlay(proxy: proxy, hoverTime: $hoverTime) }
            .frame(height: ChartHover.height)
        }
    }
}

enum ChartHover {
    static let height: CGFloat = 56

    /// Transparent layer that turns pointer position into a time on the x axis.
    static func overlay(proxy: ChartProxy, hoverTime: Binding<Date?>) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        guard let plotFrame = proxy.plotFrame else { return }
                        let x = location.x - geometry[plotFrame].origin.x
                        hoverTime.wrappedValue = proxy.value(atX: x, as: Date.self)
                    case .ended:
                        hoverTime.wrappedValue = nil
                    }
                }
        }
    }

    static func sample(in history: [Sample], near time: Date?) -> Sample? {
        guard let time, !history.isEmpty else { return nil }
        return history.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}
