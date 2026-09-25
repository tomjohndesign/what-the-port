import Darwin
import Foundation

/// `wtp`, the command-line side of the app. The app's executable runs it when
/// invoked through a symlink named `wtp`, or with `--tui`.
enum TerminalCommand {
    private static let appIdentifier = "com.whattheport.app"

    static var isRequested: Bool {
        let name = CommandLine.arguments.first.map { ($0 as NSString).lastPathComponent }
        return name == "wtp" || CommandLine.arguments.dropFirst().first == "--tui"
    }

    @MainActor static func run() -> Never {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--tui" { arguments.removeFirst() }
        // Share the menu bar app's settings: port range, processes, thresholds, integrations.
        if Bundle.main.bundleIdentifier != appIdentifier {
            UserDefaults.standard.addSuite(named: appIdentifier)
        }
        Preferences.register()

        switch arguments.first {
        case nil:
            guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { list(json: false) }
            TerminalApp.run()
        case "list", "ls":
            list(json: arguments.contains("--json"))
        case "--json":
            list(json: true)
        case "help", "-h", "--help":
            print(usage)
            exit(0)
        case "version", "-v", "--version":
            print("wtp \(version)")
            exit(0)
        default:
            FileHandle.standardError.write(Data("wtp: unknown command ‘\(arguments[0])’\n\n\(usage)\n".utf8))
            exit(64)
        }
    }

    private static let usage = """
    Every dev server on your Mac, in the terminal.

    Usage:
      wtp               Browse, open and stop servers
      wtp list          Print servers and exit
      wtp list --json   Print servers as JSON
      wtp --version     Print the version

    Press ? in wtp for keys. Settings are shared with the WhatThePort menu bar app.
    """

    /// Bundle.main doesn't follow the `wtp` symlink, so find the app from the real executable.
    private static var version: String {
        let app = Bundle.main.executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent() // MacOS
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent()
        let bundle = app.flatMap { $0.pathExtension == "app" ? Bundle(url: $0) : nil } ?? Bundle.main
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: - List

    @MainActor private static func list(json: Bool) -> Never {
        let monitor = ServerMonitor()
        monitor.handlesAlerts = false
        // CPU is measured between two scans.
        monitor.scanNow()
        usleep(500_000)
        monitor.scanNow()
        let servers = monitor.servers
        if json {
            printJSON(servers, monitor: monitor)
        } else if servers.isEmpty {
            print("Nothing listening on ports \(monitor.minPort)–\(monitor.maxPort).")
        } else {
            printTable(servers, monitor: monitor)
        }
        exit(0)
    }

    @MainActor private static func printTable(_ servers: [Server], monitor: ServerMonitor) {
        let depth = isatty(STDOUT_FILENO) == 1 ? ColorDepth.detect() : .none
        let color = depth != .none
        let isDark = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
        let headers = ["PORT", "NAME", "BRANCH", "MEMORY", "CPU", "UP", "SESSION"]
        let rows: [[String]] = servers.map { server in
            [
                ":\(server.port)",
                server.project.name,
                server.project.branch ?? "",
                Format.bytesString(server.memory),
                Format.percent(server.cpu),
                server.uptime.map(Format.shortDuration) ?? "",
                server.agent.map { agent in [agent.kind.rawValue, agent.title].compactMap { $0 }.joined(separator: " · ") } ?? "",
            ]
        }
        let rightAligned: Set<Int> = [3, 4, 5]
        let widths = headers.indices.map { column in
            ([headers[column]] + rows.map { $0[column] }).map(TextWidth.of).max() ?? 0
        }
        func format(_ cells: [String]) -> [String] {
            cells.enumerated().map { column, cell in
                let pad = String(repeating: " ", count: widths[column] - TextWidth.of(cell))
                return rightAligned.contains(column) ? pad + cell : cell + pad
            }
        }
        let dim = color ? "\u{1B}[2m" : "", reset = color ? "\u{1B}[0m" : ""
        func paint(_ pair: Palette.Pair) -> String {
            let rgb = RGB(isDark ? pair.dark : pair.light)
            if depth == .ansi256 { return "\u{1B}[38;5;\(TerminalScreen.ansi256(rgb))m" }
            let (r, g, b) = rgb.bytes
            return "\u{1B}[38;2;\(r);\(g);\(b)m"
        }
        print(dim + format(headers).joined(separator: "  ").trimmingTrailingSpaces() + reset)
        for (server, row) in zip(servers, rows) {
            var cells = format(row)
            if color {
                cells[0] = paint(Palette.ports[monitor.colorIndex(for: server.port) % Palette.ports.count]) + cells[0] + reset
                if monitor.status(of: server) == .attention {
                    cells[3] = paint(Palette.amber) + cells[3] + reset
                }
            }
            print(cells.joined(separator: "  ").trimmingTrailingSpaces())
        }
    }

    @MainActor private static func printJSON(_ servers: [Server], monitor: ServerMonitor) {
        let iso = ISO8601DateFormatter()
        let objects: [[String: Any]] = servers.map { server in
            var object: [String: Any] = [
                "port": server.port,
                "url": server.url.absoluteString,
                "pid": Int(server.pid),
                "name": server.project.name,
                "memoryBytes": server.memory,
                "cpuPercent": (server.cpu * 10).rounded() / 10,
                "processes": server.processes.map { ["pid": Int($0.pid), "name": $0.name, "memoryBytes": $0.memory] },
                "status": { () -> String in
                    switch monitor.status(of: server) {
                    case .running: return "running"
                    case .attention: return "attention"
                    case .idle: return "idle"
                    }
                }(),
                "protected": server.isProtected,
            ]
            object["branch"] = server.project.branch
            object["framework"] = server.project.framework
            object["folder"] = server.cwd
            object["command"] = server.command
            object["startedAt"] = server.startedAt.map(iso.string)
            object["conductorWorkspace"] = server.conductorWorkspace
            if let agent = server.agent {
                var session: [String: Any] = ["kind": agent.kind.rawValue, "id": agent.id]
                session["title"] = agent.title
                object["session"] = session
            }
            return object
        }
        let data = (try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        FileHandle.standardOutput.write(data)
        print()
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        var result = self
        while result.hasSuffix(" ") { result.removeLast() }
        return result
    }
}
