import Foundation

enum CommandProjection {
    static func full(_ arguments: [String]) -> String {
        arguments.map(shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct Sample: Equatable {
    let time: Date
    let memory: UInt64
    let cpu: Double
}

struct ServerProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let rawName: String
    let depth: Int
    let memory: UInt64
    var cpu: Double = 0
    var id: pid_t { pid }

    func displayedName(showFull: Bool) -> String {
        showFull ? rawName : name
    }
}

enum ServerStatus {
    case running
    case attention
    case idle
}

enum CleanUpReason: Equatable {
    case worktreeDeleted
    case idle(TimeInterval)
    case longRunning(TimeInterval)
    case leaking(UInt64)
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
    var rawCommand: String?
    var rawArguments: [String]?
    var launch: ProcArgs?
    /// Working directory of the launcher (e.g. where `npm run dev` was run).
    var launchDirectory: String?
    var startedAt: Date?
    var project: ProjectInfo
    var conductorWorkspace: String?
    var paneWorkspace: PaneWorkspace?
    var agent: AgentSession?
    var processes: [ServerProcess]
    /// Identity of every process in the tree, so we never signal a reused pid.
    var processStarts: [pid_t: Date]
    var memory: UInt64
    var cpu: Double
    var connections: Int
    var history: [Sample]
    var lastActive: Date
    var isProtected: Bool

    var id: Int { port }
    var url: URL { URL(string: "http://localhost:\(port)")! }

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
        if !cwdExists { return .idle }
        if memory >= alertThreshold || isLeaking() { return .attention }
        if idleFor > 60 * 60 { return .idle }
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

    func displayedCommand(showFull: Bool) -> String? {
        showFull ? rawCommand : command
    }
}
