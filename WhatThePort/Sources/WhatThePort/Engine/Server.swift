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
    var id: pid_t { pid }
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

    /// Short location label: Conductor workspace, git worktree, or parent folder.
    var locationLabel: String {
        if let conductorWorkspace { return conductorWorkspace }
        if let worktree = project.worktreeName { return worktree }
        guard let root = project.root ?? cwd else { return project.name }
        let parent = (root as NSString).deletingLastPathComponent
        return (parent as NSString).abbreviatingWithTildeInPath
    }
}
