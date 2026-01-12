import Foundation

struct ListeningPort: Identifiable, Hashable {
    var id: Int { port }
    let port: Int
    let pid: Int
    let process: String
}

struct PortScanner {
    // Default allowlist of common development process names
    static let defaultAllowlist: Set<String> = [
        "node", "npm", "npx", "deno", "bun",           // JavaScript/TypeScript
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",  // Python
        "ruby", "rails", "puma", "unicorn",            // Ruby
        "php", "php-fpm",                              // PHP
        "java", "gradle", "mvn",                       // Java
        "go", "air",                                   // Go
        "cargo", "rustc",                              // Rust
        "dotnet",                                      // .NET
        "beam.smp", "elixir", "mix",                   // Elixir/Erlang
        "nginx", "httpd", "apache",                    // Web servers
        "postgres", "mysql", "redis-server", "mongod", // Databases
        "docker-proxy",                                // Docker
    ]

    func scan(minPort: Int, maxPort: Int, allowlist: Set<String>) -> [ListeningPort] {
        let output = runLsof()
        let ports = parse(output)
        return ports.filter { port in
            port.port >= minPort && port.port <= maxPort && allowlist.contains(port.process)
        }
    }

    private func runLsof() -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parse(_ output: String) -> [ListeningPort] {
        var seen = Set<Int>()
        var ports: [ListeningPort] = []

        for line in output.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }

            let processName = String(cols[0])
            guard let pid = Int(cols[1]) else { continue }
            // The NAME field contains the address:port, but (LISTEN) state may be appended as last column
            let nameField = String(cols[cols.count - 2])

            guard let colonIdx = nameField.lastIndex(of: ":") else { continue }
            let portStr = nameField[nameField.index(after: colonIdx)...]
            guard let port = Int(portStr) else { continue }

            if seen.insert(port).inserted {
                ports.append(ListeningPort(port: port, pid: pid, process: processName))
            }
        }

        return ports.sorted { $0.port < $1.port }
    }

    func stopProcess(pid: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-TERM", String(pid)]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
