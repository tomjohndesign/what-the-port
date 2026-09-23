import Foundation

struct ScanConfig {
    var minPort: Int
    var maxPort: Int
    var allowlist: Set<String>
}

/// Builds the list of servers from sockets and the process table. Holds the
/// state that has to persist between scans (CPU deltas, history, caches), so it
/// must only be used from one serial queue.
final class ScanEngine: @unchecked Sendable {
    static let historyWindow: TimeInterval = 10 * 60
    static let protectedProcesses: Set<String> = ["postgres", "redis-server", "mongod", "mysqld", "mysql"]

    /// Processes that sit between a shell and the actual server, e.g. `npm run dev`.
    private static let runners: Set<String> = [
        "node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "turbo", "nx",
        "python", "python3", "Python", "uv", "poetry", "pipenv",
        "ruby", "bundle", "rails", "go", "air", "cargo", "java", "gradle", "mvn",
        "dotnet", "php", "mix", "beam.smp", "elixir",
    ]
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    private static let agentNames: Set<String> = ["claude", "codex", "Conductor"]
    /// Path fragments that identify an agent launched via a runtime like node.
    private static let agentPathMarkers = ["@anthropic-ai/claude-code", "com.conductor.app", "/codex/"]

    private let projects = ProjectResolver()
    private let agents = AgentSessionResolver()
    private var previousCPU: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
    private var histories: [String: [Sample]] = [:]
    private var lastActive: [String: Date] = [:]
    private var argsCache: [pid_t: (start: Date, args: ProcArgs?)] = [:]

    func scan(_ config: ScanConfig) -> [Server] {
        let now = Date()
        let sockets = SocketScanner.scan()
        let processes = ProcessInspector.allProcesses()

        var children: [pid_t: [pid_t]] = [:]
        for process in processes.values { children[process.ppid, default: []].append(process.pid) }

        var servers: [Server] = []
        var seenKeys = Set<String>()
        var livePids = Set<pid_t>()

        for socket in sockets.listening {
            guard socket.port >= config.minPort, socket.port <= config.maxPort,
                  config.allowlist.contains(socket.command),
                  let listener = processes[socket.pid] else { continue }

            let root = rootProcess(for: listener, in: processes)
            let tree = descendants(of: root.pid, children: children, processes: processes)
            livePids.formUnion(tree.map { $0.0.pid })

            var memory: UInt64 = 0
            var cpuPercent = 0.0
            var nodes: [ServerProcess] = []
            var starts: [pid_t: Date] = [:]
            for (process, depth) in tree {
                let usage = ProcessInspector.usage(process.pid)
                let footprint = usage?.footprint ?? 0
                memory += footprint
                if let usage {
                    if let previous = previousCPU[process.pid], usage.cpuNanoseconds >= previous.nanoseconds {
                        let elapsed = now.timeIntervalSince(previous.at)
                        if elapsed > 0 {
                            cpuPercent += Double(usage.cpuNanoseconds - previous.nanoseconds) / (elapsed * 1_000_000_000) * 100
                        }
                    }
                    previousCPU[process.pid] = (usage.cpuNanoseconds, now)
                }
                starts[process.pid] = process.startTime
                nodes.append(ServerProcess(pid: process.pid, name: displayName(for: process), depth: depth, memory: footprint))
            }

            let rootArgs = args(for: root)
            let cwd = ProcessInspector.currentDirectory(listener.pid) ?? ProcessInspector.currentDirectory(root.pid)
            // Apps that embed a node or python backend aren't dev servers.
            if cwd == "/" || [rootArgs?.executablePath, args(for: listener)?.executablePath].contains(where: { $0?.contains(".app/Contents/") == true }) {
                continue
            }
            let environment = inheritedEnvironment(from: listener, root: root, in: processes)
            let command = rootArgs.map { Self.prettyCommand($0.arguments, comm: root.comm) }
            let project = projects.resolve(cwd: cwd, command: command)

            // Restart from the highest process whose argv wasn't overwritten by a
            // title; e.g. the `sh -c "next dev -p 3000"` that npm spawns.
            let launcher = tree.map(\.0).first { Self.hasIntactArguments(args(for: $0)) } ?? root

            let key = "\(socket.port)-\(root.pid)"
            seenKeys.insert(key)
            let connections = sockets.inboundConnections[socket.port] ?? 0
            if cpuPercent >= 2 || connections > 0 || lastActive[key] == nil {
                lastActive[key] = now
            }

            var history = histories[key] ?? []
            history.append(Sample(time: now, memory: memory, cpu: cpuPercent))
            history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
            histories[key] = history

            servers.append(Server(
                port: socket.port,
                pid: listener.pid,
                rootPid: root.pid,
                processName: socket.command,
                addresses: socket.addresses,
                cwd: cwd,
                cwdExists: cwd.map { FileManager.default.fileExists(atPath: $0) } ?? true,
                command: command,
                launch: args(for: launcher),
                launchDirectory: ProcessInspector.currentDirectory(launcher.pid) ?? cwd,
                startedAt: root.startTime,
                project: project,
                conductorWorkspace: environment["CONDUCTOR_WORKSPACE_NAME"],
                agent: agents.resolve(environment: environment, cwd: cwd),
                processes: nodes,
                processStarts: starts,
                memory: memory,
                cpu: cpuPercent,
                connections: connections,
                history: history,
                lastActive: lastActive[key] ?? now,
                isProtected: Self.protectedProcesses.contains(socket.command)
            ))
        }

        histories = histories.filter { seenKeys.contains($0.key) }
        lastActive = lastActive.filter { seenKeys.contains($0.key) }
        previousCPU = previousCPU.filter { livePids.contains($0.key) }
        argsCache = argsCache.filter { processes[$0.key] != nil }
        return servers
    }

    // MARK: - Process tree

    /// Climbs from the listening process to the command the user actually ran,
    /// e.g. from `next-server` up to `npm run dev`. Stops at shells, terminals
    /// and coding agents so stopping a server never takes its launcher with it.
    private func rootProcess(for listener: ProcSnapshot, in processes: [pid_t: ProcSnapshot]) -> ProcSnapshot {
        var current = listener
        while true {
            guard current.ppid > 1, let parent = processes[current.ppid] else { break }
            if Self.runners.contains(parent.comm), !isAgent(parent) {
                current = parent
                continue
            }
            // Package managers run scripts through `sh -c`; step over that shell
            // only when a package manager sits directly above it.
            if Self.shells.contains(parent.comm), parent.ppid > 1,
               let grandparent = processes[parent.ppid],
               Self.runners.contains(grandparent.comm), !isAgent(grandparent) {
                current = grandparent
                continue
            }
            break
        }
        return current
    }

    private func isAgent(_ process: ProcSnapshot) -> Bool {
        if Self.agentNames.contains(process.comm) { return true }
        guard let args = args(for: process) else { return false }
        let joined = ([args.executablePath] + args.arguments.prefix(3)).joined(separator: " ")
        return Self.agentPathMarkers.contains(where: joined.contains)
    }

    private func descendants(of root: pid_t, children: [pid_t: [pid_t]], processes: [pid_t: ProcSnapshot]) -> [(ProcSnapshot, Int)] {
        guard let rootProcess = processes[root] else { return [] }
        var result: [(ProcSnapshot, Int)] = []
        func visit(_ process: ProcSnapshot, depth: Int) {
            result.append((process, depth))
            for child in (children[process.pid] ?? []).sorted() {
                if let childProcess = processes[child] { visit(childProcess, depth: depth + 1) }
            }
        }
        visit(rootProcess, depth: 0)
        return result
    }

    /// Merges environments from the listener up through its launcher. Tools that
    /// rename their process (Next.js sets `process.title = "next-server"`)
    /// overwrite the memory their environment is read from, so the session
    /// variables often only survive on a parent like `npm`.
    private func inheritedEnvironment(from listener: ProcSnapshot, root: ProcSnapshot, in processes: [pid_t: ProcSnapshot]) -> [String: String] {
        var chain: [ProcSnapshot] = [listener]
        var current = listener
        var extraHops = 2
        while current.ppid > 1, let parent = processes[current.ppid], chain.count < 10 {
            if current.pid == root.pid || chain.contains(where: { $0.pid == root.pid }) {
                guard extraHops > 0 else { break }
                extraHops -= 1
            }
            chain.append(parent)
            current = parent
        }
        var environment: [String: String] = [:]
        for process in chain.reversed() {
            environment.merge(args(for: process)?.environment ?? [:]) { _, closer in closer }
        }
        return environment
    }

    private static func hasIntactArguments(_ args: ProcArgs?) -> Bool {
        guard let args else { return false }
        let parts = args.arguments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.count > 1 || (parts.count == 1 && !parts[0].contains(" "))
    }

    private func args(for process: ProcSnapshot) -> ProcArgs? {
        if let cached = argsCache[process.pid], cached.start == process.startTime { return cached.args }
        let args = ProcessInspector.arguments(process.pid)
        argsCache[process.pid] = (process.startTime, args)
        return args
    }

    // MARK: - Names

    private func displayName(for process: ProcSnapshot) -> String {
        guard let args = args(for: process), !args.arguments.isEmpty else { return process.comm }
        let command = Self.prettyCommand(args.arguments, comm: process.comm)
        // `process.title` renames like "next-server (v16.0.0)" read better without the version.
        if let paren = command.range(of: " (") { return String(command[..<paren.lowerBound]) }
        return command
    }

    /// Turns raw argv into what someone would have typed, e.g.
    /// `node /…/npm-cli.js run dev` becomes `npm run dev`.
    static func prettyCommand(_ arguments: [String], comm: String) -> String {
        let arguments = arguments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = arguments.first else { return comm }
        var parts = arguments
        let executable = (first as NSString).lastPathComponent

        if executable == "node" || executable == "bun" || executable == "deno", parts.count > 1 {
            let script = parts[1]
            let tools = ["npm", "npx", "pnpm", "yarn", "vite", "next", "astro", "nuxt", "storybook", "tsx", "turbo"]
            if let tool = tools.first(where: { script.contains("/\($0)/") || script.contains("/\($0)-cli") || (script as NSString).lastPathComponent == $0 }) {
                parts = [tool] + parts.dropFirst(2)
            } else if script.hasPrefix("/") || script.hasPrefix(".") {
                parts = [(script as NSString).lastPathComponent] + parts.dropFirst(2)
            }
        } else {
            parts[0] = executable
        }
        return parts.map { $0.hasPrefix("/") ? ($0 as NSString).lastPathComponent : $0 }.joined(separator: " ")
    }
}
