import Foundation

struct Sample: Equatable {
    let time: Date
    let memory: UInt64
    let cpu: Double
}

struct ServerProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let depth: Int
    let memory: UInt64
    var cpu: Double = 0
    var id: pid_t { pid }
}

enum ServerStatus {
    case running
    case attention
    case idle
    case paused
}

enum CleanUpReason: Equatable {
    case worktreeDeleted
    case idle(TimeInterval)
    case longRunning(TimeInterval)
    case leaking(UInt64)
}

/// How the Servers page orders its rows. Ties fall back to port.
enum ServerSort: String, CaseIterable, Identifiable {
    case usage, recency, name, port

    var id: String { rawValue }

    func sorted(_ servers: [Server]) -> [Server] {
        servers.sorted { a, b in
            switch self {
            case .usage where a.memory != b.memory:
                return a.memory > b.memory
            case .recency where a.startedAt != b.startedAt:
                return (a.startedAt ?? .distantPast) > (b.startedAt ?? .distantPast)
            case .name:
                let order = a.listTitle.localizedStandardCompare(b.listTitle)
                return order == .orderedSame ? a.port < b.port : order == .orderedAscending
            default:
                return a.port < b.port
            }
        }
    }
}

/// A block of rows on the Servers page: native servers first, with no header,
/// then one group per compose project and one per runtime for other containers.
struct ServerSection: Identifiable {
    let id: String
    /// Nil for native servers.
    let title: String?
    /// The runtime and compose folder's branch, which its rows then leave out.
    let detail: String?
    let servers: [Server]

    var memory: UInt64 { ServerResources(servers).memory }

    /// Keeps each section's rows in the order given. `sort` orders the groups;
    /// nil keeps them in the order they first appear, so a list under the
    /// pointer holds still.
    static func arrange(_ servers: [Server], sort: ServerSort?) -> [ServerSection] {
        let native = servers.filter { $0.container == nil }
        var order: [String] = []
        var byGroup: [String: [Server]] = [:]
        for server in servers {
            guard let key = server.container?.groupKey else { continue }
            if byGroup[key] == nil { order.append(key) }
            byGroup[key, default: []].append(server)
        }
        var groups = order.compactMap { key -> ServerSection? in
            guard let rows = byGroup[key], let container = rows.first?.container else { return nil }
            let project = container.composeProject
            let detail = project == nil ? nil : [container.runtime.name, rows.first?.project.branch].compactMap { $0 }.joined(separator: " · ")
            return ServerSection(id: key, title: project ?? container.runtime.name, detail: detail, servers: rows)
        }
        if let sort {
            groups.sort { a, b in
                let lowest = { (section: ServerSection) in section.servers.map(\.port).min() ?? 0 }
                switch sort {
                case .usage where a.memory != b.memory:
                    return a.memory > b.memory
                case .recency:
                    let newest = { (section: ServerSection) in section.servers.compactMap(\.startedAt).max() ?? .distantPast }
                    if newest(a) != newest(b) { return newest(a) > newest(b) }
                case .name:
                    let order = (a.title ?? "").localizedStandardCompare(b.title ?? "")
                    if order != .orderedSame { return order == .orderedAscending }
                default:
                    break
                }
                return lowest(a) < lowest(b)
            }
        }
        return (native.isEmpty ? [] : [ServerSection(id: "native", title: nil, detail: nil, servers: native)]) + groups
    }
}

/// The Pane terminal a server was started from.
struct PaneWorkspace {
    let name: String
    /// `pane://open?pane=<id>&panel=<id>` focuses that terminal in Pane.
    let link: URL

    /// Pane sets these in every terminal it opens.
    init?(environment: [String: String]) {
        guard let pane = environment["PANE_SESSION_ID"], let path = environment["PANE_WORKSPACE_PATH"] else { return nil }
        var components = URLComponents(string: "pane://open")!
        components.queryItems = [URLQueryItem(name: "pane", value: pane)]
        if let panel = environment["PANE_PANEL_ID"] { components.queryItems?.append(URLQueryItem(name: "panel", value: panel)) }
        guard let link = components.url else { return nil }
        self.name = (path as NSString).lastPathComponent
        self.link = link
    }
}

/// A listening port and everything we know about the process tree behind it.
struct Server: Identifiable {
    let port: Int
    let pid: pid_t
    let rootPid: pid_t
    let processName: String
    var addresses: [String]
    var cwd: String?
    var cwdExists: Bool
    var command: String?
    var launch: ProcArgs?
    /// Working directory of the launcher (e.g. where `npm run dev` was run).
    var launchDirectory: String?
    var startedAt: Date?
    var project: ProjectInfo
    var conductorWorkspace: String?
    var paneWorkspace: PaneWorkspace?
    var agent: AgentSession?
    /// Set when the port is published by a Docker or OrbStack container. The
    /// listening pid is then the runtime's helper, which must never be signalled:
    /// `processes` and `processStarts` stay empty and Stop goes to the container.
    var container: ContainerInfo? = nil
    var processes: [ServerProcess]
    /// Identity of every process in the tree, so we never signal a reused pid.
    var processStarts: [pid_t: Date]
    /// What Pause freezes: `processStarts`, except a launcher a terminal is waiting on.
    var pauseTargets: [pid_t: Date]
    var memory: UInt64
    var cpu: Double
    var connections: Int
    var history: [Sample]
    var lastActive: Date
    var isProtected: Bool
    /// Read from the process itself, so it also covers Ctrl-Z, and the menu bar
    /// app and `wtp` always agree.
    var isPaused: Bool

    var id: Int { port }
    /// Which server this is across scans, for alerts and Clean up. Containers
    /// share their runtime helper's pid, so they're told apart by container id.
    var identityKey: String { "\(port)-\(container?.id ?? String(rootPid))" }
    var url: URL { URL(string: "http://localhost:\(port)")! }

    /// Protected native databases stay quiet. Containers are only protected
    /// from Clean up, and still warn when they use too much memory.
    var getsAlerts: Bool { !isProtected || container != nil }

    /// The name a list row leads with: the branch, or for containers the
    /// compose service, since the group header already names the project.
    var listTitle: String {
        if let container { return container.composeService ?? container.name }
        return project.displayName
    }

    /// `listTitle` with the branch's prefix, for the row's tooltip.
    var fullListTitle: String {
        container == nil ? project.branch ?? project.name : listTitle
    }

    /// Idle time says nothing about a container, whose traffic can stay inside
    /// its compose network where the Mac never sees it.
    var isIdle: Bool { container == nil && idleFor > 60 * 60 }

    var uptime: TimeInterval? { startedAt.map { Date().timeIntervalSince($0) } }
    var idleFor: TimeInterval { Date().timeIntervalSince(lastActive) }

    /// Memory growth across the recorded history window (up to 10 minutes).
    var memoryGrowth: Int64 {
        guard let first = history.first, let last = history.last,
              last.time.timeIntervalSince(first.time) >= 120 else { return 0 }
        return Int64(last.memory) - Int64(first.memory)
    }

    func isLeaking(threshold: UInt64 = 500 * 1_048_576) -> Bool {
        memoryGrowth >= Int64(threshold)
    }

    func status(alertThreshold: UInt64) -> ServerStatus {
        if isPaused { return .paused }
        if !cwdExists { return .idle }
        if memory >= alertThreshold || isLeaking() { return .attention }
        if isIdle { return .idle }
        return .running
    }

    /// Short location label: Conductor or Pane workspace, git worktree, or parent folder.
    var locationLabel: String {
        if let conductorWorkspace { return conductorWorkspace }
        if let paneWorkspace { return paneWorkspace.name }
        if let worktree = project.worktreeName { return worktree }
        guard let root = project.root ?? cwd else { return project.name }
        let parent = (root as NSString).deletingLastPathComponent
        return (parent as NSString).abbreviatingWithTildeInPath
    }
}
