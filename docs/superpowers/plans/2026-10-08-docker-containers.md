# Docker Containers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show ports published by running Docker containers as server rows with container memory and CPU, and stop or restart them through `docker`.

**Architecture:** A new `DockerScanner` runs `docker ps` on every scan (2 s timeout) and keeps a background `docker stats` sampler whose latest values are cached. `ScanEngine` turns each published host port into a `Server` with a `container` field, one synthetic process carrying the container's stats, and `isProtected = true` so Clean up skips it. It also drops the lsof row Docker's own process holds on that port. `ProcessControl` routes Stop and Restart for container rows to `docker stop` and `docker restart`.

**Tech Stack:** Swift 5.9 package (SwiftUI, Swift Testing), `docker` CLI, Next.js 14 marketing site (TypeScript).

**Spec:** `docs/superpowers/specs/2026-10-08-docker-containers-design.md`

## Global Constraints

- Work on branch `feature/docker-containers`. Commit after every task with a short message that says what changed and doesn't explain decisions.
- Never use an em dash in code, comments, strings or docs.
- Swift tests: from `WhatThePort/`, run
  `D=/Library/Developer/CommandLineTools/Library/Developer; swift test -Xswiftc -F$D/Frameworks -Xlinker -F$D/Frameworks -Xlinker -rpath -Xlinker $D/Frameworks -Xlinker -rpath -Xlinker $D/usr/lib`
  (this Mac has Command Line Tools only; plain `swift test` fails with "no such module 'Testing'"). The baseline is 33 passing tests.
- Below, `$TEST` means that command, optionally followed by `--filter <SuiteName>`.
- The only signal-based stop path (`kill`) must never target a container row. Container rows have empty `processStarts`.
- Containers are never suggested or auto-stopped by Clean up.
- `Preferences.showDocker` defaults to on. With it off, the app behaves exactly as before this change.
- Match existing style: `L10n.text`/`L10n.format` for menu bar UI strings, English-only strings in `wtp`, no new dependencies.
- Never commit `public/WhatThePort.dmg` or `public/updates/`.

## Review Focus

1. Docker not installed or daemon stopped: no Docker rows, no errors, scans stay fast. `docker ps` failing or timing out returns an empty snapshot (Task 2 test: `run` returns nil on non-zero exit and on timeout).
2. A container whose Compose folder was deleted, or which has no Compose labels, still shows up with the container name as its title and can still be stopped. It must not be shown as "Worktree deleted" (Task 3 test `containerWithoutComposeHasNameAndNoFolder`).
3. Two containers with the same pid 0 in their synthetic process must not merge in totals (Task 3 test `containersAreCountedSeparatelyInTotals`).
4. A container publishing IPv4 and IPv6 for the same port gives one row, not two (Task 1 test `mergesIPv4AndIPv6`).
5. The stats sampler must not spin when `docker stats` fails instantly (Task 2: sleep 2 s after an empty result). It also stops within about 10 s once scans stop asking (toggle off or no containers).

---

### Task 1: Parse docker output

**Files:**
- Create: `WhatThePort/Sources/WhatThePort/Engine/DockerScanner.swift`
- Test: `WhatThePort/Tests/WhatThePortTests/DockerScannerTests.swift`

**Interfaces:**
- Produces:
  - `struct PublishedPort: Equatable { let port: Int; var addresses: [String] }`
  - `struct DockerContainer: Equatable { let id: String; let name: String; let image: String; var ports: [PublishedPort]; var composeProject: String?; var composeService: String?; var workingDirectory: String? }`
  - `struct DockerStats: Equatable { let memory: UInt64; let cpu: Double }`
  - `struct DockerSnapshot { var containers: [DockerContainer] = []; var stats: [String: DockerStats] = [:] }` (stats keyed by short container id)
  - `final class DockerScanner` with statics `psFormat`, `statsFormat`, `parseContainers(_:) -> [DockerContainer]`, `parsePorts(_:) -> [PublishedPort]`, `parseStats(_:) -> [String: DockerStats]`, `parseBytes(_:) -> UInt64?`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import WhatThePort

struct DockerScannerTests {
    @Test func parsesComposeContainer() {
        let line = "ed34fb53ee1d\tm2a-web-ui\telemental-live-control-web-ui\t0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp\telemental-live-control\tweb-ui\t/Users/andy/workspace/elemental-live-control"
        let containers = DockerScanner.parseContainers(line + "\n")
        #expect(containers == [DockerContainer(
            id: "ed34fb53ee1d", name: "m2a-web-ui", image: "elemental-live-control-web-ui",
            ports: [PublishedPort(port: 3000, addresses: ["0.0.0.0", "::"])],
            composeProject: "elemental-live-control", composeService: "web-ui",
            workingDirectory: "/Users/andy/workspace/elemental-live-control")])
    }

    @Test func plainContainerHasNoComposeFields() {
        let containers = DockerScanner.parseContainers("9dbf750448b3\tcache\tredis:7\t127.0.0.1:6379->6379/tcp\t\t\t\n")
        #expect(containers.count == 1)
        #expect(containers[0].composeProject == nil)
        #expect(containers[0].composeService == nil)
        #expect(containers[0].workingDirectory == nil)
    }

    @Test func skipsContainersWithoutPublishedPortsAndMalformedLines() {
        let output = "b2715eb5051e\tagent\tagent-image\t9091/tcp\tproj\tagent\t/tmp\nnot a container line\n"
        #expect(DockerScanner.parseContainers(output).isEmpty)
    }

    @Test func mergesIPv4AndIPv6() {
        #expect(DockerScanner.parsePorts("0.0.0.0:9091->9091/tcp, [::]:9091->9091/tcp")
            == [PublishedPort(port: 9091, addresses: ["0.0.0.0", "::"])])
    }

    @Test func expandsRangesAndIgnoresUDPAndUnpublished() {
        let ports = DockerScanner.parsePorts("0.0.0.0:3000-3001->3000-3001/tcp, 0.0.0.0:5353->5353/udp, 8080/tcp, 127.0.0.1:18080->8080/tcp")
        #expect(ports.map(\.port) == [3000, 3001, 18080])
        #expect(ports.last?.addresses == ["127.0.0.1"])
    }

    @Test func parsesStatsAndUnits() {
        let output = "05fdd2b755f6\t15.84MiB / 7.748GiB\t0.30%\ned34fb53ee1d\t1.5GiB / 7.748GiB\t112.5%\nabc123def456\t-- / --\t--\n"
        let stats = DockerScanner.parseStats(output)
        #expect(stats.count == 2)
        #expect(stats["05fdd2b755f6"] == DockerStats(memory: UInt64(15.84 * 1_048_576), cpu: 0.3))
        #expect(stats["ed34fb53ee1d"] == DockerStats(memory: UInt64(1.5 * 1_073_741_824), cpu: 112.5))
    }

    @Test func parsesByteUnits() {
        #expect(DockerScanner.parseBytes("512B") == 512)
        #expect(DockerScanner.parseBytes("2KiB") == 2048)
        #expect(DockerScanner.parseBytes("1.5kB") == 1500)
        #expect(DockerScanner.parseBytes("3MB") == 3_000_000)
        #expect(DockerScanner.parseBytes("--") == nil)
        #expect(DockerScanner.parseBytes("12parsecs") == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$TEST --filter DockerScannerTests`
Expected: build FAILS with "cannot find 'DockerScanner' in scope".

- [ ] **Step 3: Write the parsing code**

```swift
import Foundation

/// A host port a container publishes, and the host addresses it's bound to.
struct PublishedPort: Equatable {
    let port: Int
    var addresses: [String]
}

struct DockerContainer: Equatable {
    let id: String
    let name: String
    let image: String
    var ports: [PublishedPort]
    var composeProject: String?
    var composeService: String?
    /// The folder `docker compose up` ran in.
    var workingDirectory: String?
}

struct DockerStats: Equatable {
    let memory: UInt64
    let cpu: Double
}

struct DockerSnapshot {
    var containers: [DockerContainer] = []
    /// Keyed by short container id, as `docker ps` prints it.
    var stats: [String: DockerStats] = [:]
}

/// Reads running containers through the `docker` CLI, so it works with any
/// runtime the CLI's current context points at (Docker Desktop, OrbStack, Colima).
final class DockerScanner: @unchecked Sendable {
    static let psFormat = "{{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Label \"com.docker.compose.project\"}}\t{{.Label \"com.docker.compose.service\"}}\t{{.Label \"com.docker.compose.project.working_dir\"}}"
    static let statsFormat = "{{.ID}}\t{{.MemUsage}}\t{{.CPUPerc}}"

    // MARK: - Parsing

    /// Containers that publish at least one TCP port on the host.
    static func parseContainers(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7 else { return nil }
            let ports = parsePorts(fields[3])
            guard !ports.isEmpty else { return nil }
            func label(_ value: String) -> String? { value.isEmpty ? nil : value }
            return DockerContainer(id: fields[0], name: fields[1], image: fields[2], ports: ports,
                                   composeProject: label(fields[4]), composeService: label(fields[5]),
                                   workingDirectory: label(fields[6]))
        }
    }

    /// Reads `0.0.0.0:3000->3000/tcp, [::]:3000->3000/tcp` style lists. Ports
    /// without `->` aren't published to the host.
    static func parsePorts(_ text: String) -> [PublishedPort] {
        var result: [PublishedPort] = []
        for entry in text.components(separatedBy: ", ") {
            guard entry.hasSuffix("/tcp"), let arrow = entry.range(of: "->") else { continue }
            let host = entry[..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let address = host[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            let bounds = host[host.index(after: colon)...].split(separator: "-").compactMap { Int($0) }
            guard (1...2).contains(bounds.count), let first = bounds.first, let last = bounds.last, first <= last else { continue }
            for port in first...last {
                if let index = result.firstIndex(where: { $0.port == port }) {
                    if !result[index].addresses.contains(address) { result[index].addresses.append(address) }
                } else {
                    result.append(PublishedPort(port: port, addresses: [address]))
                }
            }
        }
        return result
    }

    static func parseStats(_ output: String) -> [String: DockerStats] {
        var result: [String: DockerStats] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count == 3,
                  let usage = fields[1].components(separatedBy: " / ").first,
                  let memory = parseBytes(usage),
                  let cpu = Double(fields[2].trimmingCharacters(in: .whitespaces).dropLast()) else { continue }
            result[fields[0]] = DockerStats(memory: memory, cpu: cpu)
        }
        return result
    }

    /// Docker prints memory as `15.84MiB` or `1.5kB`.
    static func parseBytes(_ text: String) -> UInt64? {
        let units: [String: Double] = [
            "B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
            "KiB": 1024, "MiB": 1_048_576, "GiB": 1_073_741_824, "TiB": 1_099_511_627_776,
        ]
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let split = trimmed.firstIndex(where: \.isLetter),
              let value = Double(trimmed[..<split]),
              let unit = units[String(trimmed[split...])] else { return nil }
        return UInt64(value * unit)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$TEST --filter DockerScannerTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add WhatThePort/Sources/WhatThePort/Engine/DockerScanner.swift WhatThePort/Tests/WhatThePortTests/DockerScannerTests.swift
git commit -m "Parse docker ps and docker stats output"
```

---

### Task 2: Run docker and sample stats in the background

**Files:**
- Modify: `WhatThePort/Sources/WhatThePort/Engine/DockerScanner.swift`
- Test: `WhatThePort/Tests/WhatThePortTests/DockerScannerTests.swift`

**Interfaces:**
- Consumes: Task 1 types and parsers.
- Produces:
  - `static let executable: String?`: path to the docker CLI, or nil.
  - `static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String?`: stdout on exit status 0, nil on failure or timeout.
  - `func snapshot() -> DockerSnapshot`: running containers plus the latest cached stats. It starts the sampler when there are containers.

- [ ] **Step 1: Write the failing tests**

Append inside `struct DockerScannerTests`:

```swift
    @Test func runReturnsOutputOnSuccess() {
        #expect(DockerScanner.run("/bin/echo", ["hi"], timeout: 2) == "hi\n")
    }

    @Test func runReturnsNilOnFailure() {
        #expect(DockerScanner.run("/usr/bin/false", [], timeout: 2) == nil)
        #expect(DockerScanner.run("/nonexistent/docker", [], timeout: 2) == nil)
    }

    @Test func runGivesUpAfterTimeout() {
        let start = Date()
        #expect(DockerScanner.run("/bin/sleep", ["5"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$TEST --filter DockerScannerTests`
Expected: build FAILS with "type 'DockerScanner' has no member 'run'".

- [ ] **Step 3: Implement the runner, CLI lookup and sampler**

Add to `DockerScanner`, above `// MARK: - Parsing`:

```swift
    /// Apps launched from Finder have no shell PATH, so look where each runtime installs the CLI.
    // ponytail: found once per launch; installing docker later needs an app restart.
    static let executable: String? = {
        let home = NSHomeDirectory()
        return ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", home + "/.orbstack/bin/docker",
                home + "/.docker/bin/docker", home + "/.rd/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    private let lock = NSLock()
    private var stats: [String: DockerStats] = [:]
    private var isSampling = false
    private var lastRequest = Date.distantPast

    /// Running containers and the latest stats. A missing CLI, stopped daemon or
    /// hung call gives an empty snapshot.
    func snapshot() -> DockerSnapshot {
        guard let docker = Self.executable,
              let output = Self.run(docker, ["ps", "--format", Self.psFormat], timeout: 2) else { return DockerSnapshot() }
        let containers = Self.parseContainers(output)
        guard !containers.isEmpty else { return DockerSnapshot() }
        lock.lock()
        defer { lock.unlock() }
        lastRequest = Date()
        if !isSampling {
            isSampling = true
            DispatchQueue.global(qos: .utility).async { self.sample(docker) }
        }
        return DockerSnapshot(containers: containers, stats: stats)
    }

    /// `docker stats` takes about two seconds because it measures CPU over an
    /// interval, so it runs back to back off the scan queue. Stops once scans
    /// haven't asked for containers in 10 seconds.
    private func sample(_ docker: String) {
        while true {
            let fresh = Self.run(docker, ["stats", "--no-stream", "--format", Self.statsFormat], timeout: 5).map(Self.parseStats) ?? [:]
            lock.lock()
            if Date().timeIntervalSince(lastRequest) > 10 {
                stats = [:]
                isSampling = false
                lock.unlock()
                return
            }
            stats = fresh
            lock.unlock()
            if fresh.isEmpty { Thread.sleep(forTimeInterval: 2) }
        }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$TEST --filter DockerScannerTests`
Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add WhatThePort/Sources/WhatThePort/Engine/DockerScanner.swift WhatThePort/Tests/WhatThePortTests/DockerScannerTests.swift
git commit -m "Run docker ps with a timeout and sample docker stats in the background"
```

---

### Task 3: Container rows in the scan

**Files:**
- Modify: `WhatThePort/Sources/WhatThePort/Engine/Server.swift` (add `container`, `canRestart`, `locationLabel`)
- Modify: `WhatThePort/Sources/WhatThePort/Engine/ScanEngine.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Engine/ServerResources.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Engine/Preferences.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Engine/ServerMonitor.swift` (`scanConfig`)
- Test: `WhatThePort/Tests/WhatThePortTests/ScanEngineTests.swift`

**Interfaces:**
- Consumes: `DockerScanner().snapshot()`, `DockerSnapshot`, `DockerContainer`, `DockerStats` (Tasks 1-2).
- Produces:
  - `Server.container: DockerContainer?` (last stored property, default `nil`).
  - `Server.canRestart: Bool`.
  - `ScanConfig.showDocker: Bool` (default `true`).
  - `Preferences.showDocker = "integrations.docker"` (registered default `true`).
  - `ScanEngine.scan(_:sockets:processes:docker:now:)` with `docker: DockerSnapshot = DockerSnapshot()`.

- [ ] **Step 1: Write the failing tests**

In `ScanEngineTests.Fixture`, add a property and change `scan(after:)`:

```swift
        var docker = DockerSnapshot()
```

```swift
        func scan(after seconds: Double = 0) -> [Server] {
            engine.scan(config, sockets: sockets, processes: processes, docker: docker, now: epoch.addingTimeInterval(seconds))
        }
```

Add a helper below `listen` in the fixture:

```swift
        func container(_ id: String, name: String, ports: [Int], memory: UInt64 = 0, cpu: Double = 0, folder: String? = nil) {
            docker.containers.append(DockerContainer(id: id, name: name, image: "\(name):latest",
                                                     ports: ports.map { PublishedPort(port: $0, addresses: ["0.0.0.0"]) },
                                                     composeProject: folder.map { ($0 as NSString).lastPathComponent },
                                                     composeService: name, workingDirectory: folder))
            docker.stats[id] = DockerStats(memory: memory, cpu: cpu)
        }
```

Add tests to `ScanEngineTests`:

```swift
    @Test func containerPortsBecomeRowsAndHideDockersOwnListener() {
        let f = Fixture()
        f.config.allowlist.insert("com.docker.backend")
        f.process(99, name: "com.docker.backend")
        f.listen(99, port: 3000)
        f.process(20)
        f.listen(20, port: 4000)
        f.container("ed34fb53ee1d", name: "web", ports: [3000], memory: 15_000_000, cpu: 1.5, folder: NSTemporaryDirectory())
        let rows = f.scan()
        #expect(rows.map(\.port) == [3000, 4000])
        let web = rows[0]
        #expect(web.container?.name == "web")
        #expect(web.project.name == "web")
        #expect(web.project.branch == nil)
        #expect(web.memory == 15_000_000)
        #expect(web.cpu == 1.5)
        #expect(web.processStarts.isEmpty)
        #expect(web.isProtected)
        #expect(web.canRestart)
        #expect(web.locationLabel == "Docker · \((NSTemporaryDirectory() as NSString).lastPathComponent)")
    }

    @Test func containerRowsHonourPortRangeAndToggle() {
        let f = Fixture()
        f.container("aaa", name: "db", ports: [2000, 5432])
        #expect(f.scan().map(\.port) == [5432])
        f.config.showDocker = false
        #expect(f.scan().isEmpty)
    }

    @Test func containerWithoutComposeHasNameAndNoFolder() {
        let f = Fixture()
        f.container("bbb", name: "cache", ports: [6379])
        let row = f.scan()[0]
        #expect(row.project.name == "cache")
        #expect(row.cwd == nil)
        #expect(row.cwdExists)
        #expect(row.locationLabel == "Docker · cache:latest")
    }

    @Test func containerHistoryGrowsAcrossScans() {
        let f = Fixture()
        f.container("ccc", name: "api", ports: [8000], memory: 100)
        _ = f.scan()
        f.docker.stats["ccc"] = DockerStats(memory: 300, cpu: 0)
        let row = f.scan(after: 2)[0]
        #expect(row.history.map(\.memory) == [100, 300])
    }

    @Test func containersAreCountedSeparatelyInTotals() {
        let f = Fixture()
        f.container("aaa", name: "one", ports: [3000, 3001], memory: 100)
        f.container("bbb", name: "two", ports: [3002], memory: 50)
        let resources = ServerResources(f.scan())
        #expect(resources.memory == 150)
        #expect(resources.memoryByPort == [3000: 50, 3001: 50, 3002: 50])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$TEST --filter ScanEngineTests`
Expected: build FAILS with "extra argument 'docker' in call".

- [ ] **Step 3: Add `container`, `canRestart` and the Docker location label to `Server`**

In `Server.swift`, after `var isProtected: Bool` add:

```swift
    var container: DockerContainer? = nil
```

After `var idleFor` add:

```swift
    /// Containers restart through docker; processes need their command and folder.
    var canRestart: Bool { container != nil || (launch != nil && cwdExists) }
```

At the top of `locationLabel`, before `if let conductorWorkspace`:

```swift
        if let container { return "Docker · \(container.composeProject ?? container.image)" }
```

Update its doc comment to: `/// Short location label: Docker, Conductor or Pane workspace, git worktree, or parent folder.`

- [ ] **Step 4: Count containers separately in `ServerResources`**

Replace the `Identity` struct and its construction:

```swift
    private struct Identity: Hashable {
        let pid: pid_t
        let startedAt: Date
        /// Container rows all carry pid 0.
        let container: String?
    }
```

```swift
                let identity = Identity(pid: process.pid, startedAt: server.processStarts[process.pid] ?? .distantPast,
                                        container: server.container?.id)
```

- [ ] **Step 5: Add the preference and config flag**

`Preferences.swift`, under `static let linkPane`:

```swift
    static let showDocker = "integrations.docker"
```

and in `register()` after `linkPane: true,`:

```swift
            showDocker: true,
```

`ScanEngine.swift`, `ScanConfig`, after `var showBranches = true`:

```swift
    var showDocker = true
```

`ServerMonitor.swift`, `scanConfig`, change the last argument line to:

```swift
                   showBranches: defaults.bool(forKey: Preferences.showBranches),
                   showDocker: defaults.bool(forKey: Preferences.showDocker))
```

- [ ] **Step 6: Add container rows to `ScanEngine`**

Add a property next to `private let agents`:

```swift
    private let docker = DockerScanner()
```

Replace the two `scan` entry points' signatures and the start of the loop:

```swift
    func scan(_ config: ScanConfig) -> [Server] {
        scan(config, sockets: SocketScanner.scan(), processes: ProcessInspector.allProcesses(),
             docker: config.showDocker ? docker.snapshot() : DockerSnapshot(), now: Date())
    }

    /// Snapshot inputs keep ownership and sampling testable without real processes.
    func scan(_ config: ScanConfig, sockets: SocketScan, processes: [pid_t: ProcSnapshot],
              docker: DockerSnapshot = DockerSnapshot(), now: Date) -> [Server] {
        let ownership = ProcessTree(processes: processes, sockets: sockets)
        var sampled: [pid_t: (memory: UInt64, cpu: Double)] = [:]
        let containers = config.showDocker ? docker.containers : []
        // Docker's own process holds published ports; the container row replaces it.
        let publishedPorts = Set(containers.flatMap { $0.ports.map(\.port) })

        var servers: [Server] = []
        var seenKeys = Set<String>()
        var livePids = Set<pid_t>()

        for socket in sockets.listening {
            guard socket.port >= config.minPort, socket.port <= config.maxPort,
                  !publishedPorts.contains(socket.port),
                  Self.isAllowed(socket.command, allowlist: config.allowlist),
                  let listener = processes[socket.pid] else { continue }
```

Replace the existing history block inside the loop:

```swift
            let connections = sockets.inboundConnections[socket.port] ?? 0
            if cpuPercent >= 2 || connections > 0 || lastActive[key] == nil {
                lastActive[key] = now
            }

            var history = histories[key] ?? []
            history.append(Sample(time: now, memory: memory, cpu: cpuPercent))
            history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
            histories[key] = history
```

with:

```swift
            let connections = sockets.inboundConnections[socket.port] ?? 0
            let activity = track(key, memory: memory, cpu: cpuPercent, connections: connections, now: now)
```

and in that `Server(...)` call replace `history: history,` and `lastActive: lastActive[key] ?? now,` with:

```swift
                history: activity.history,
                lastActive: activity.lastActive,
```

After the socket loop, before `histories = histories.filter`, add:

```swift
        for container in containers {
            let stats = docker.stats[container.id] ?? DockerStats(memory: 0, cpu: 0)
            var project = projects.resolve(cwd: container.workingDirectory, command: nil)
            project.name = container.name
            project.branch = nil
            for published in container.ports where published.port >= config.minPort && published.port <= config.maxPort {
                let key = "\(published.port)-\(container.id)"
                seenKeys.insert(key)
                let connections = sockets.inboundConnections[published.port] ?? 0
                let activity = track(key, memory: stats.memory, cpu: stats.cpu, connections: connections, now: now)
                servers.append(Server(
                    port: published.port,
                    pid: 0,
                    rootPid: 0,
                    processName: "docker",
                    addresses: published.addresses,
                    cwd: container.workingDirectory,
                    // The container keeps running even if its Compose folder is gone.
                    cwdExists: true,
                    command: nil,
                    launch: nil,
                    launchDirectory: nil,
                    startedAt: nil,
                    project: project,
                    conductorWorkspace: nil,
                    paneWorkspace: nil,
                    agent: nil,
                    processes: [ServerProcess(pid: 0, name: container.name, depth: 0, memory: stats.memory, cpu: stats.cpu)],
                    processStarts: [:],
                    memory: stats.memory,
                    cpu: stats.cpu,
                    connections: connections,
                    history: activity.history,
                    lastActive: activity.lastActive,
                    // Containers are often long-lived databases, so Clean up leaves them alone.
                    isProtected: true,
                    container: container
                ))
            }
        }
        servers.sort { $0.port < $1.port }
```

Add the helper under the `scan` function:

```swift
    /// Records a sample and returns the server's history and when it was last active.
    private func track(_ key: String, memory: UInt64, cpu: Double, connections: Int, now: Date) -> (history: [Sample], lastActive: Date) {
        if cpu >= 2 || connections > 0 || lastActive[key] == nil {
            lastActive[key] = now
        }
        var history = histories[key] ?? []
        history.append(Sample(time: now, memory: memory, cpu: cpu))
        history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
        histories[key] = history
        return (history, lastActive[key] ?? now)
    }
```

- [ ] **Step 7: Run all tests**

Run: `$TEST`
Expected: all tests pass (33 baseline + 10 from Tasks 1-2 + 5 new = 48).

- [ ] **Step 8: Commit**

```bash
git add WhatThePort/Sources/WhatThePort/Engine WhatThePort/Tests
git commit -m "Show Docker container ports as servers with container memory and CPU"
```

---

### Task 4: Stop and restart containers through docker

**Files:**
- Modify: `WhatThePort/Sources/WhatThePort/Engine/ProcessControl.swift`

**Interfaces:**
- Consumes: `Server.container`, `DockerScanner.executable`, `DockerScanner.run` (Tasks 2-3).
- Produces: `ProcessControl.stop` and `ProcessControl.restart` handle container rows. Their signatures are unchanged.

This path shells out to a real daemon, so it is verified manually in Task 6 rather than with a unit test.

- [ ] **Step 1: Branch `stop` and `restart` on containers**

At the top of `static func stop(_ server: Server, completion: (() -> Void)? = nil)`:

```swift
        if let container = server.container {
            docker("stop", container) { _ in completion?() }
            return
        }
```

At the top of `static func restart(_ server: Server, completion: ((Bool) -> Void)? = nil)`, before the `guard`:

```swift
        if let container = server.container {
            docker("restart", container) { completion?($0) }
            return
        }
```

Add below `restart`:

```swift
    /// Containers stop through docker. Signalling the process that holds the
    /// port would take Docker, and every other container, down with it.
    private static func docker(_ command: String, _ container: DockerContainer, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global().async {
            let succeeded = DockerScanner.executable.flatMap { DockerScanner.run($0, [command, container.id], timeout: 30) } != nil
            DispatchQueue.main.async { completion(succeeded) }
        }
    }
```

- [ ] **Step 2: Build and run all tests**

Run: `$TEST`
Expected: 48 tests pass.

- [ ] **Step 3: Commit**

```bash
git add WhatThePort/Sources/WhatThePort/Engine/ProcessControl.swift
git commit -m "Stop and restart container rows with docker stop and docker restart"
```

---

### Task 5: Menu bar UI, wtp and settings

**Files:**
- Modify: `WhatThePort/Sources/WhatThePort/UI/ServerDetailView.swift`
- Modify: `WhatThePort/Sources/WhatThePort/UI/SettingsView.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Terminal/TerminalApp.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Terminal/TerminalCommand.swift`
- Modify: `WhatThePort/Sources/WhatThePort/Resources/{en,de,fr,es,zh-Hans,he,ja,uk}.lproj/Localizable.strings`
- Test: existing `LocalizationTests.resourceTablesHaveMatchingKeysAndArgumentPositions`

**Interfaces:**
- Consumes: `Server.container`, `Server.canRestart`, `Preferences.showDocker`, `DockerScanner.executable`.

- [ ] **Step 1: Add the strings to all eight tables**

Append to the end of each `Localizable.strings` file:

| Key | en | de | fr | es | zh-Hans | he | ja | uk |
|---|---|---|---|---|---|---|---|---|
| `Stop container` | Stop container | Container stoppen | Arrêter le conteneur | Detener contenedor | 停止容器 | עצירת הקונטיינר | コンテナを停止 | Зупинити контейнер |
| `Restart container` | Restart container | Container neu starten | Redémarrer le conteneur | Reiniciar contenedor | 重启容器 | הפעלה מחדש של הקונטיינר | コンテナを再起動 | Перезапустити контейнер |
| `Image` | Image | Image | Image | Imagen | 镜像 | אימג׳ | イメージ | Образ |
| `Show containers` | Show containers | Container anzeigen | Afficher les conteneurs | Mostrar contenedores | 显示容器 | הצגת קונטיינרים | コンテナを表示 | Показувати контейнери |
| `Ports published by running containers` | Ports published by running containers | Ports, die laufende Container veröffentlichen | Ports publiés par les conteneurs en cours d’exécution | Puertos publicados por contenedores en ejecución | 运行中的容器发布的端口 | פורטים שמפורסמים על ידי קונטיינרים פעילים | 実行中のコンテナが公開しているポート | Порти, опубліковані запущеними контейнерами |

Format, for example in `de.lproj`:

```
"Stop container" = "Container stoppen";
"Restart container" = "Container neu starten";
"Image" = "Image";
"Show containers" = "Container anzeigen";
"Ports published by running containers" = "Ports, die laufende Container veröffentlichen";
```

Run: `$TEST --filter LocalizationTests`
Expected: pass. If it fails with a duplicate-key error for `Image`, the key already exists; remove the new line.

- [ ] **Step 2: Detail view**

In `ServerDetailView.swift`:
- Restart button: replace `.disabled(server.launch == nil || !server.cwdExists)` with `.disabled(!server.canRestart)`.
- Stop button: replace `help: L10n.format("Stop %d processes", server.processes.count)` with
  `help: server.container != nil ? L10n.text("Stop container") : L10n.format("Stop %d processes", server.processes.count)`.
- `restartHelp`: add as its first line `if server.container != nil { return L10n.text("Restart container") }`.
- `secondaryRows`: after the `Framework` row, add

```swift
        if let container = server.container {
            rows.append(InfoRow(label: L10n.text("Image"), tooltip: container.image) { Text(container.image).font(Theme.mono).foregroundStyle(Theme.text2) })
        }
```

- [ ] **Step 3: Settings toggle**

In the Integrations settings view in `SettingsView.swift`, add next to the other `@AppStorage` lines:

```swift
    @AppStorage(Preferences.showDocker) private var docker = true
```

and after the `Section("Git") { ... }` block:

```swift
            Section("Docker") {
                Toggle(isOn: $docker) {
                    SettingLabel(L10n.text("Show containers"), caption: DockerScanner.executable != nil ? L10n.text("Ports published by running containers") : L10n.text("Not installed"))
                }
            }
```

- [ ] **Step 4: `wtp` terminal UI**

In `TerminalApp.swift`:
- The Restart action (`ServerAction(label: server.agent.map { ... } ?? "Restart", ...)`): change the label to
  `server.container != nil ? "Restart container" : server.agent.map { "Restart · runs outside \($0.kind.rawValue)" } ?? "Restart"`
  and `isEnabled:` to `server.canRestart`.
- The Stop action label: `server.container != nil ? "Stop container" : "Stop \(count) \(count == 1 ? "process" : "processes")"`.
- `private func restart(_ server: Server)`: change the guard to `guard server.canRestart else {`.
- The stop confirmation `question`: change the last span to
  `Span(server.container != nil ? "?" : " and its \(count) \(count == 1 ? "process" : "processes")?", palette.text1)`.
- In the secondary info rows, after the `Command` row:

```swift
        if let container = server.container {
            secondary.append(row("Image", [Span(container.image, palette.text2)], middle: true))
        }
```

In `TerminalCommand.swift` `printJSON`, after the `pane` block:

```swift
            if let container = server.container {
                object["container"] = ["id": container.id, "name": container.name, "image": container.image]
            }
```

- [ ] **Step 5: Build and run all tests**

Run: `$TEST`
Expected: 48 tests pass.

- [ ] **Step 6: Commit**

```bash
git add WhatThePort/Sources WhatThePort/Tests
git commit -m "Show container details and Docker setting in the app and wtp"
```

---

### Task 6: Verify against real Docker

**Files:** none (manual verification). Needs Docker Desktop running with the user's existing containers (for example `m2a-web-ui` on 3000, `m2a-postgres` on 5432).

- [ ] **Step 1: Snapshot listing**

Run from `WhatThePort/`: `swift run WhatThePort --snapshot ../.context/docker-snapshot`
Expected: printed lines include `:3000  m2a-web-ui ... procs=1`, `:5432  m2a-postgres`, `:6379  m2a-redis`, and no `com.docker.backend` rows. Memory may be 0 B on this single scan, because stats arrive about 2 s later.

- [ ] **Step 2: Live app**

Run `swift run WhatThePort` and open the menu bar popover. Wait 5 seconds.
Expected:
- Container rows appear, with "Docker · elemental-live-control" in the subtitle.
- Memory roughly matches `docker stats --no-stream`.
- The detail view shows an Image row and a growing memory chart.

- [ ] **Step 3: Stop and restart**

Create a throwaway container: `docker run -d --rm --name wtp-test -p 3999:80 busybox httpd -f -p 80`.
- In the app, open `:3999`, press Restart, and confirm with `docker ps` that its "Up" time reset.
- Press Stop. Confirm the row disappears, `docker ps` no longer lists `wtp-test`, and the other containers are still running (`docker ps | wc -l` unchanged minus one).
- Never press Stop on the user's own containers.

- [ ] **Step 4: Toggle and Clean up**

- In Settings → Integrations, turn off "Show containers". Container rows disappear within one scan. Turn it back on.
- Open Clean up and confirm no container rows are listed.

- [ ] **Step 5: Docker not running**

Skip this step if quitting Docker Desktop would disrupt the user. Ask first.

---

### Task 7: Marketing site, docs and screenshots

**Files:**
- Modify: `app/components/servers.ts`, `app/components/App.tsx`, `scripts/app-strings.mjs`, `app/components/appStrings.json` (generated)
- Modify: `README.md`, `content/whattheport.md`, `content/guides/eaddrinuse-address-already-in-use.md`
- Modify: `docs/images/servers.jpg` (refresh if the demo's Servers screenshot is affected)

**Interfaces:**
- Consumes: the native behaviour from Tasks 3-5: row title is the container name, subtitle `Docker · <project>`, detail has an Image row, Stop is labelled "Stop container", Restart is "Restart container", there is no "Running for", and Clean up never lists containers.

- [ ] **Step 1: Demo data**

In `servers.ts`, add `container?: true` to the `Server` type with comment `// Docker container row: no uptime, never in Clean up.`. Add the entry below before the `:6006` entry, so the list stays ordered by port:

```ts
  {
    port: '5432',
    name: 'api-db',
    branch: 'api-db',
    status: 'on',
    memory: 148,
    cpu: 1,
    cpuNote: 'quiet',
    uptime: '',
    context: { text: 'Docker · api' },
    lines: () => ({ context: 'Docker · api', running: '' }),
    container: true,
    chart: 'steady',
    spark: 'M0 11 L4 11 L8 10.5 L12 11 L16 10.5 L20 11 L24 10.5 L28 11 L32 10.5 L36 11 L40 10.5 L44 11',
    processes: [{ pid: 70001, command: 'api-db', memory: 148, cpu: 1 }],
    info: [
      ['Folder', '~/Code/api'],
      ['Image', 'postgres:16'],
    ],
  },
```

Run: `npm run test:resources`
Expected: "Demo resources: ... passed."

- [ ] **Step 2: Demo behaviour in `App.tsx`**

- Detail view: hide the "Running for" text when `server.container`. Restart button `title`: `server.container ? l.text('Restart container') : ...existing...`. Stop button `aria-label`/`title`: `server.container ? l.text('Stop container') : l.text('Stop')`.
- Info rows: give `Image` the mono style, as for `PID` and `Command` (`label === 'PID' || label === 'Command' || label === 'Image'`).
- Clean up list: where the list is rendered while `cleaning`, filter out `s.container`, matching the native `isProtected` filter.

In `scripts/app-strings.mjs`, add `'Image', 'Stop container', 'Restart container'` to `KEYS`, then run `node scripts/app-strings.mjs` to regenerate `appStrings.json`.

- [ ] **Step 3: Copy and docs**

- `Copy.tsx`: leave `TOOLS` alone. That list is about agent sessions, and Docker is not one. No other section lists what WhatThePort detects, so Copy.tsx needs no change.
- `README.md` feature list (line 50 area): add `- **Sees Docker too** - Ports published by running containers show up with the container's memory and CPU. Stop and Restart use docker, so Docker itself keeps running`. Line 114 Integrations: append `, Docker containers`. Line 119 "How it works": add the sentence `Docker containers come from the docker CLI's current context (Docker Desktop, OrbStack, Colima), with memory and CPU from docker stats.`
- `content/whattheport.md`: add the same bullet to the feature list, and the same sentence to the how-it-works paragraph (line 49).
- `content/guides/eaddrinuse-address-already-in-use.md` line 74: replace with `- **Docker Desktop**: a published container port is held by Docker itself. Use \`docker ps\` and \`docker stop\` rather than killing Docker, or stop the container from WhatThePort, which lists it by name.` Test the commands on this Mac first (`docker ps`, `docker stop <name>` on the `wtp-test` container from Task 6).

- [ ] **Step 4: Verify in a browser**

Run `npm run dev` from the repo root. Using the Chrome tools, check desktop (1440 px) and mobile (390 px):
- The `:5432` row appears with "Docker · api".
- Its detail shows Image `postgres:16` and no "Running for".
- Simulated Restart and Stop work.
- Clean up does not list it.
- The popover doesn't overflow with six rows.
- Check the console for errors. Save screenshots in `.context/` (e.g. `.context/docker-demo-desktop.png`, `.context/docker-demo-mobile.png`).

If `docs/images/servers.jpg` shows the Servers list, retake it from the native app with the container row visible. Otherwise leave it.

- [ ] **Step 5: Build**

Run: `npm run build`
Expected: success. If `check-download.mjs` fails because there is no production download locally, run `node scripts/app-strings.mjs --check && npx next build` instead and note it.

- [ ] **Step 6: Commit**

```bash
git add app scripts README.md content docs/images
git commit -m "Show a Docker container in the site demo and docs"
```
