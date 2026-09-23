import Darwin
import Foundation

enum ProcessControl {
    static let forceQuitDelay: TimeInterval = 3

    /// Sends SIGTERM to every process in the server's tree, then SIGKILL to
    /// anything still running after a grace period. Each pid is re-checked
    /// against its start time first so a reused pid is never signalled.
    static func stop(_ server: Server, completion: (() -> Void)? = nil) {
        let targets = server.processStarts
        for pid in targets.keys where isSameProcess(pid, startedAt: targets[pid]) {
            kill(pid, SIGTERM)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + forceQuitDelay) {
            for pid in targets.keys where isSameProcess(pid, startedAt: targets[pid]) {
                kill(pid, SIGKILL)
            }
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    /// Stops the server and relaunches the same command, in the same directory,
    /// with the same environment. Output goes to ~/Library/Logs/WhatThePort.
    static func restart(_ server: Server, completion: ((Bool) -> Void)? = nil) {
        guard let launch = server.launch, let cwd = server.launchDirectory ?? server.cwd,
              FileManager.default.fileExists(atPath: cwd),
              let command = shellCommand(for: launch) else {
            completion?(false)
            return
        }
        stop(server) {
            DispatchQueue.global().async {
                // Give the kernel a moment to release the port.
                for _ in 0..<20 where !isPortFree(server.port) { usleep(250_000) }
                let launched = spawn(command, environment: launch.environment, cwd: cwd, port: server.port)
                DispatchQueue.main.async { completion?(launched) }
            }
        }
    }

    /// The command line to rerun. Tools like npm and Next.js overwrite their
    /// argv with a title (`npm run dev -p 3000`), which is what was typed, so we
    /// run that through a shell. Intact argv is re-quoted as-is.
    static func shellCommand(for launch: ProcArgs) -> String? {
        let args = launch.arguments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = args.first else { return nil }
        let shells: Set<String> = ["sh", "bash", "zsh", "dash"]
        if shells.contains((first as NSString).lastPathComponent), args.count >= 3, args[1] == "-c" {
            return args[2]
        }
        if args.count == 1, first.contains(" ") {
            if let paren = first.range(of: " (") { return String(first[..<paren.lowerBound]) }
            return first
        }
        let executable = first.hasPrefix("/") ? first : launch.executablePath
        return ([executable] + args.dropFirst()).map(shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        if value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func spawn(_ command: String, environment: [String: String], cwd: String, port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = environment.isEmpty ? ProcessInfo.processInfo.environment : environment
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WhatThePort")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("port-\(port).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func isSameProcess(_ pid: pid_t, startedAt: Date?) -> Bool {
        guard pid > 1, pid != getpid(), let snapshot = ProcessInspector.snapshot(pid) else { return false }
        guard let startedAt else { return true }
        return abs(snapshot.startTime.timeIntervalSince(startedAt)) < 1
    }

    private static func isPortFree(_ port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return true }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result != 0
    }
}
