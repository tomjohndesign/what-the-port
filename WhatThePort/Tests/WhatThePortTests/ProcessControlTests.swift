import Darwin
import Foundation
import Testing
@testable import WhatThePort

struct ProcessControlTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WTP_TEST_HOME"] != nil))
    func restartAndStopPreserveOwnedLaunchInputs() async throws {
        guard let homePath = ProcessInfo.processInfo.environment["WTP_TEST_HOME"] else { return }
        let home = URL(fileURLWithPath: homePath).standardizedFileURL
        #expect(FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL == home)

        let fixture = home.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let port = try availablePort()
        let fingerprint = fixture.appendingPathComponent("fingerprint.json")
        let secret = "wtp-process-control-env-secret"
        let python = try pythonExecutable()
        let script = """
        import http.server, json, os, sys
        with open(sys.argv[2], "w") as output:
            json.dump({"argv": sys.argv[1:], "secret": os.environ["WTP_TEST_ENV_SECRET"]}, output)
        http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), http.server.SimpleHTTPRequestHandler).serve_forever()
        """
        let arguments = [python, "-c", script, String(port), fingerprint.path, "--api-key=wtp-process-control-argv-secret"]
        let environment = ["WTP_TEST_ENV_SECRET": secret]
        let original = try start(executable: python, arguments: Array(arguments.dropFirst()), environment: environment, directory: fixture)
        defer {
            if original.isRunning { original.terminate() }
        }
        try await waitForListener(port)
        let originalStart = try #require(ProcessInspector.snapshot(original.processIdentifier)?.startTime)
        let server = makeServer(port: port, pid: original.processIdentifier, start: originalStart, launch: .init(
            executablePath: python, arguments: arguments, environment: environment
        ), directory: fixture)

        UserDefaults.standard.set(0.1, forKey: Preferences.forceQuitSeconds)
        let restarted = await withCheckedContinuation { continuation in
            ProcessControl.restart(server) { continuation.resume(returning: $0) }
        }
        #expect(restarted)
        try await waitForListener(port)
        let relaunchedPID = try #require(SocketScanner.scan().listenerPidsByPort[port]?.first)
        let relaunchedStart = try #require(ProcessInspector.snapshot(relaunchedPID)?.startTime)
        defer {
            ProcessControl.stop(makeServer(port: port, pid: relaunchedPID, start: relaunchedStart, launch: nil, directory: fixture))
        }
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: fingerprint)) as? [String: Any]
        #expect(result?["argv"] as? [String] == [String(port), fingerprint.path, "--api-key=wtp-process-control-argv-secret"])
        #expect(result?["secret"] as? String == secret)

        let stale = makeServer(port: port, pid: relaunchedPID, start: .distantPast, launch: nil, directory: fixture)
        ProcessControl.stop(stale)
        try await Task.sleep(for: .milliseconds(200))
        #expect(SocketScanner.scan().listenerPidsByPort[port]?.contains(relaunchedPID) == true)

        ProcessControl.stop(makeServer(port: port, pid: relaunchedPID, start: relaunchedStart, launch: nil, directory: fixture))
        try await waitForNoListener(port)
    }

    private func start(executable: String, arguments: [String], environment: [String: String], directory: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func pythonExecutable() throws -> String {
        let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":") ?? []
        for directory in paths {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("python3").path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func makeServer(port: Int, pid: pid_t, start: Date, launch: ProcArgs?, directory: URL) -> Server {
        Server(
            port: port, pid: pid, rootPid: pid, processName: "Python", addresses: ["127.0.0.1"],
            cwd: directory.path, cwdExists: true, command: "python3", rawCommand: launch.map { CommandProjection.full($0.arguments) },
            rawArguments: launch?.arguments, launch: launch, launchDirectory: directory.path, startedAt: start,
            project: ProjectInfo(name: "fixture"), conductorWorkspace: nil, paneWorkspace: nil, agent: nil,
            processes: [ServerProcess(pid: pid, name: "Python", rawName: "Python", depth: 0, memory: 0)],
            processStarts: [pid: start], memory: 0, cpu: 0, connections: 0, history: [],
            lastActive: Date(), isProtected: false
        )
    }

    private func availablePort() throws -> Int {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socketFD) }
        guard socketFD >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        guard withUnsafePointer(to: &address, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }) == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &length)
            }
        }
        guard result == 0 else { throw POSIXError(.EADDRNOTAVAIL) }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private func waitForListener(_ port: Int) async throws {
        for _ in 0..<100 {
            if SocketScanner.scan().listenerPidsByPort[port] != nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func waitForNoListener(_ port: Int) async throws {
        for _ in 0..<100 {
            if SocketScanner.scan().listenerPidsByPort[port] == nil { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CocoaError(.fileWriteUnknown)
    }
}
