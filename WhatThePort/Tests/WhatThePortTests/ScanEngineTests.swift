import Foundation
import Testing
@testable import WhatThePort

struct ScanEngineTests {
    private final class Fixture {
        var processes: [pid_t: ProcSnapshot] = [:]
        var sockets = SocketScan()
        var usages: [pid_t: ProcUsage] = [:]
        var arguments: [pid_t: ProcArgs] = [:]
        var reads: [pid_t: Int] = [:]
        var runtimes: [ContainerRuntime: RuntimeSnapshot] = [:]
        var containerQueries: [Set<ContainerRuntime>] = []
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        var config = ScanConfig(minPort: 3000, maxPort: 9999, allowlist: ["node", "Python", "python3"],
                                linkClaude: false, linkCodex: false, linkConductor: false, showBranches: false)
        lazy var engine = ScanEngine(inspector: .init(
            usage: { [unowned self] pid in
                reads[pid, default: 0] += 1
                return usages[pid]
            },
            arguments: { [unowned self] in arguments[$0] },
            currentDirectory: { _ in NSTemporaryDirectory() },
            containers: { [unowned self] wanted in
                containerQueries.append(wanted)
                return runtimes.filter { wanted.contains($0.key) }
            }
        ))

        /// OrbStack's helper, which holds every published container port.
        func orbStackHelper(_ pid: pid_t, memory: UInt64 = 4_000_000_000) {
            processes[pid] = ProcSnapshot(pid: pid, ppid: 1, comm: "OrbStack Helper", startTime: epoch)
            usages[pid] = ProcUsage(footprint: memory, cpuNanoseconds: 0)
            arguments[pid] = ProcArgs(executablePath: "/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper",
                                      arguments: ["OrbStack Helper", "vmgr"], environment: [:])
        }

        /// A running container as the monitor reports it, with one stats sample unless `memory` is nil.
        func container(_ name: String, image: String, ports: Set<Int>, memory: UInt64? = 0, cpu: Double = 0,
                       runtime: ContainerRuntime = .orbStack(), service: String? = nil,
                       workingDirectory: String? = NSTemporaryDirectory()) {
            let info = ContainerInfo(id: name + "-id", name: name, image: image, runtime: runtime, publishedPorts: ports,
                                     composeProject: service == nil ? nil : "shop", composeService: service,
                                     workingDirectory: service == nil ? nil : workingDirectory)
            runtimes[runtime, default: RuntimeSnapshot()].containers.append(info)
            runtimes[runtime]!.listedAt = epoch
            runtimes[runtime]!.startedAt[info.id] = epoch
            if let memory { sample(name, memory: memory, cpu: cpu, runtime: runtime) }
        }

        func sample(_ name: String, memory: UInt64, cpu: Double = 0, after seconds: Double = 0, runtime: ContainerRuntime = .orbStack()) {
            runtimes[runtime, default: RuntimeSnapshot()].samples[name + "-id"] =
                ContainerSample(memory: memory, cpu: cpu, at: epoch.addingTimeInterval(seconds))
        }

        func process(_ pid: pid_t, parent: pid_t = 1, name: String = "node", memory: UInt64 = 100) {
            processes[pid] = ProcSnapshot(pid: pid, ppid: parent, comm: name, startTime: epoch)
            usages[pid] = ProcUsage(footprint: memory, cpuNanoseconds: 0)
            arguments[pid] = ProcArgs(executablePath: "/usr/local/bin/\(name)", arguments: [name, "server.js"], environment: [:])
        }

        func listen(_ pid: pid_t, port: Int) {
            sockets.listenerPidsByPort[port, default: []].insert(pid)
            if !sockets.listening.contains(where: { $0.port == port }) {
                sockets.listening.append(ListeningSocket(port: port, pid: pid, command: processes[pid]!.comm, addresses: ["127.0.0.1"]))
            }
        }

        func scan(after seconds: Double = 0) -> [Server] {
            engine.scan(config, sockets: sockets, processes: processes, now: epoch.addingTimeInterval(seconds))
        }
    }

    @Test func pausedServersReportPausedAndDontGoIdle() {
        let f = Fixture()
        f.process(10, memory: 3_000_000_000)
        f.listen(10, port: 3000)
        #expect(f.scan()[0].isPaused == false)
        #expect(f.scan()[0].status(alertThreshold: 1) == .attention)

        f.processes[10]?.isStopped = true
        let paused = f.scan(after: 7200)[0]
        #expect(paused.isPaused)
        #expect(paused.status(alertThreshold: 1) == .paused)
        #expect(paused.lastActive == f.epoch.addingTimeInterval(7200))

        f.processes[10]?.isStopped = false
        #expect(f.scan(after: 7201)[0].lastActive == f.epoch.addingTimeInterval(7200))
    }

    @Test func pauseLeavesATerminalsLauncherRunning() {
        let f = Fixture()
        f.process(5, name: "zsh")
        f.process(10, parent: 5, name: "npm")
        f.process(20, parent: 10)
        f.listen(20, port: 3000)
        let launched = f.scan()[0]
        #expect(launched.rootPid == 10)
        #expect(Set(launched.processStarts.keys) == [10, 20])
        #expect(Set(launched.pauseTargets.keys) == [20])

        // Started directly, the server itself is the command the shell waits on.
        f.process(30, parent: 5)
        f.listen(30, port: 3001)
        #expect(Set(f.scan()[1].pauseTargets.keys) == [30])

        // Without a shell above it, nothing is waiting, so the whole tree freezes.
        f.process(40, name: "npm")
        f.process(50, parent: 40)
        f.listen(50, port: 3002)
        #expect(Set(f.scan()[2].pauseTargets.keys) == [40, 50])
    }

    @Test func sortsByUsageRecencyNameAndPort() {
        let f = Fixture()
        f.config.showBranches = false
        f.process(10, memory: 100)
        f.process(20, memory: 300)
        f.process(30, memory: 200)
        f.process(40, memory: 200)
        f.processes[20] = ProcSnapshot(pid: 20, ppid: 1, comm: "node", startTime: f.epoch.addingTimeInterval(30))
        f.processes[30] = ProcSnapshot(pid: 30, ppid: 1, comm: "node", startTime: f.epoch.addingTimeInterval(60))
        f.listen(40, port: 3004)
        f.listen(30, port: 3003)
        f.listen(20, port: 3002)
        f.listen(10, port: 3001)
        var rows = f.scan()
        for (index, name) in ["delta", "alpha", "Charlie", "bravo"].enumerated() {
            rows[index].project.name = name
        }
        func ports(_ sort: ServerSort) -> [Int] { sort.sorted(rows).map(\.port) }
        #expect(ports(.port) == [3001, 3002, 3003, 3004])
        #expect(ports(.usage) == [3002, 3003, 3004, 3001])
        #expect(ports(.recency) == [3003, 3002, 3001, 3004])
        #expect(ports(.name) == [rows[1].port, rows[3].port, rows[2].port, rows[0].port])
    }

    @MainActor @Test func pausesOnlyTheChosenServers() async throws {
        func listener(port: Int) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            process.arguments = ["-l", String(port)]
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            return process
        }
        let processes = try [38151, 38152, 38153].map(listener)
        defer { processes.forEach { kill($0.processIdentifier, SIGKILL) } }
        try await Task.sleep(for: .milliseconds(300))

        let monitor = ServerMonitor()
        monitor.minPort = 38151
        monitor.maxPort = 38153
        monitor.allowlist = ["nc"]
        monitor.scanNow()
        #expect(monitor.servers.map(\.port).sorted() == [38151, 38152, 38153])

        monitor.pause(monitor.servers.filter { $0.port != 38153 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(processes.map { ProcessInspector.snapshot($0.processIdentifier)?.isStopped } == [true, true, false])
        #expect(monitor.servers.filter(\.isPaused).map(\.port).sorted() == [38151, 38152])

        // Pausing again doesn't toggle a paused server back on.
        monitor.pause(monitor.servers)
        try await Task.sleep(for: .milliseconds(100))
        #expect(processes.map { ProcessInspector.snapshot($0.processIdentifier)?.isStopped } == [true, true, true])
    }

    @Test func pausesResumesAndStopsARealProcess() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let pid = process.processIdentifier

        let f = Fixture()
        f.config.allowlist.insert("sleep")
        f.process(pid)
        f.processes[pid] = ProcessInspector.snapshot(pid)
        f.listen(pid, port: 3000)
        let server = try #require(f.scan().first)

        func isStopped() async -> Bool {
            try? await Task.sleep(for: .milliseconds(100))
            return ProcessInspector.snapshot(pid)?.isStopped ?? false
        }

        #expect(await isStopped() == false)
        ProcessControl.pause(server)
        #expect(await isStopped())
        ProcessControl.resume(server)
        #expect(await isStopped() == false)

        // A paused process still gets to handle SIGTERM rather than waiting for SIGKILL.
        ProcessControl.pause(server)
        #expect(await isStopped())
        ProcessControl.stop(server)
        for _ in 0..<20 where process.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        #expect(!process.isRunning)
        #expect(process.terminationStatus == SIGTERM)
    }

    @Test func siblingsHaveSeparateResourcesAndStopTargets() {
        let f = Fixture()
        f.process(10, memory: 1000) // shared orchestrator must not be charged to either row
        f.process(20, parent: 10, memory: 200)
        f.process(21, parent: 20, name: "esbuild", memory: 30)
        f.process(30, parent: 10, memory: 500)
        f.listen(20, port: 3000)
        f.listen(20, port: 3001)
        f.listen(30, port: 8000)
        let rows = f.scan()
        #expect(rows.map(\.memory) == [230, 230, 500])
        #expect(rows.map(\.rootPid) == [20, 20, 30])
        #expect(Set(rows[0].processStarts.keys) == [20, 21])
        #expect(Set(rows[2].processStarts.keys) == [30])
        #expect(f.reads == [20: 1, 21: 1, 30: 1])
        let resources = ServerResources(rows)
        #expect(resources.memory == 730)
        #expect(resources.memoryByPort == [3000: 115, 3001: 115, 8000: 500])
        #expect(ServerResources(Array(rows.prefix(2))).memory == 230)
    }

    @Test func cpuIsSampledOnceAndSharedByEveryPort() {
        let f = Fixture()
        f.process(20)
        f.listen(20, port: 3000)
        f.listen(20, port: 3001)
        _ = f.scan()
        f.usages[20] = ProcUsage(footprint: 100, cpuNanoseconds: 500_000_000)
        let rows = f.scan(after: 1)
        #expect(rows.map(\.cpu) == [50, 50])
        #expect(rows.map { $0.history.last!.cpu } == [50, 50])
        #expect(ServerResources(rows).cpu == 50)
        #expect(f.reads[20] == 2)
    }

    @Test func growthInOneServerDoesNotFlagItsSiblings() {
        let f = Fixture()
        f.process(10)
        f.process(20, parent: 10)
        f.process(30, parent: 10)
        f.listen(20, port: 3000)
        f.listen(30, port: 8000)
        _ = f.scan()
        f.usages[30] = ProcUsage(footprint: 100 + 600 * 1_048_576, cpuNanoseconds: 0)
        let rows = f.scan(after: 121)
        #expect(rows[0].memoryGrowth == 0)
        #expect(!rows[0].isLeaking())
        #expect(rows[1].memoryGrowth == 600 * 1_048_576)
        #expect(rows[1].isLeaking())
    }

    @Test func hiddenListenersStillLimitOwnership() {
        let f = Fixture()
        f.process(10)
        f.process(20, parent: 10)
        f.process(30, parent: 10, name: "not-allowed")
        f.listen(20, port: 3000)
        f.listen(30, port: 12000) // outside both the port range and allowlist
        let rows = f.scan()
        #expect(rows.count == 1)
        #expect(rows[0].rootPid == 20)
        #expect(Set(rows[0].processStarts.keys) == [20])
    }

    @Test func packageManagerAndWorkersStayWithAnExclusiveServer() {
        let f = Fixture()
        f.process(5, name: "zsh")
        f.process(10, parent: 5, name: "npm")
        f.process(15, parent: 10, name: "sh")
        f.process(20, parent: 15)
        f.process(21, parent: 20, name: "esbuild")
        f.listen(20, port: 3000)
        let row = f.scan()[0]
        #expect(row.rootPid == 10)
        #expect(Set(row.processStarts.keys) == [10, 15, 20, 21])
        #expect(row.launch?.executablePath == "/usr/local/bin/npm")
    }

    @Test func restartKeepsExclusiveShellBelowSharedRunner() {
        let f = Fixture()
        f.process(10, name: "npm")
        f.process(15, parent: 10, name: "sh")
        f.arguments[15] = ProcArgs(executablePath: "/bin/sh", arguments: ["sh", "-c", "next dev"], environment: [:])
        f.process(20, parent: 15)
        f.arguments[20] = ProcArgs(executablePath: "/usr/local/bin/node", arguments: ["next-server (v16.0.0)"], environment: [:])
        f.process(30, parent: 10)
        f.listen(20, port: 3000)
        f.listen(30, port: 8000)
        let row = f.scan()[0]
        #expect(row.rootPid == 15)
        #expect(Set(row.processStarts.keys) == [15, 20])
        #expect(row.launch?.arguments == ["sh", "-c", "next dev"])
    }

    @Test func restartNeverChoosesAnUnrelatedHelper() {
        let f = Fixture()
        f.process(10, name: "npm")
        f.arguments[10] = ProcArgs(executablePath: "/usr/local/bin/npm", arguments: ["npm run dev"], environment: [:])
        f.process(11, parent: 10, name: "esbuild") // traversed before the listener
        f.process(20, parent: 10)
        f.listen(20, port: 3000)
        #expect(f.scan()[0].launch?.executablePath == "/usr/local/bin/node")
    }

    @Test func sharedSocketReloadersKeepTheirWorkers() {
        let f = Fixture()
        f.process(10, name: "Python")
        f.process(20, parent: 10, name: "Python")
        f.process(30, parent: 10, name: "Python")
        f.listen(20, port: 8000) // lsof may report a worker before its parent
        f.listen(10, port: 8000)
        f.listen(30, port: 8000)
        let rows = f.scan()
        #expect(rows.count == 1)
        #expect(rows[0].rootPid == 10)
        #expect(Set(rows[0].processStarts.keys) == [10, 20, 30])
    }

    @Test func nestedIndependentServiceIsExcluded() {
        let f = Fixture()
        f.process(10)
        f.process(20, parent: 10, name: "sh")
        f.process(30, parent: 20)
        f.process(40, parent: 10, name: "esbuild")
        f.listen(10, port: 3000)
        f.listen(30, port: 8000)
        let rows = f.scan()
        #expect(Set(rows[0].processStarts.keys) == [10, 40])
        #expect(Set(rows[1].processStarts.keys) == [20, 30])
    }

    @Test func reusedPIDStartsFreshCPUAndHistory() {
        let f = Fixture()
        f.process(20)
        f.listen(20, port: 3000)
        _ = f.scan()
        f.usages[20] = ProcUsage(footprint: 200, cpuNanoseconds: 1_000_000_000)
        f.processes[20] = ProcSnapshot(pid: 20, ppid: 1, comm: "node", startTime: f.epoch.addingTimeInterval(1))
        let row = f.scan(after: 2)[0]
        #expect(row.cpu == 0)
        #expect(row.history.count == 1)
        #expect(row.memoryGrowth == 0)
    }

    @Test func sharedSocketParserPreservesAllOwnersAndAddresses() {
        let scan = SocketScanner.parse("""
        p10
        cPython
        f1
        n127.0.0.1:8000
        TST=LISTEN
        f2
        n[::1]:8000
        TST=LISTEN
        p20
        cPython
        f1
        n127.0.0.1:8000
        TST=LISTEN
        """)
        #expect(scan.listening.count == 1)
        #expect(scan.listening[0].addresses == ["127.0.0.1", "[::1]"])
        #expect(scan.listenerPidsByPort[8000] == [10, 20])
    }

    @Test func frameworkPythonIsDetectedButEmbeddedBackendsStayHidden() {
        let f = Fixture()
        f.process(20, name: "Python")
        f.listen(20, port: 8765)
        f.process(30, name: "Python")
        f.listen(30, port: 8766)
        f.arguments[20] = ProcArgs(executablePath: "/opt/homebrew/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python", arguments: ["python3", "-m", "http.server"], environment: [:])
        f.arguments[30] = ProcArgs(executablePath: "/Applications/Editor.app/Contents/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python", arguments: ["python3", "backend.py"], environment: [:])
        #expect(f.scan().map(\.port) == [8765])
        #expect(ScanEngine.isEmbeddedAppExecutable("/Applications/Editor.app/Contents/MacOS/node"))
        #expect(ScanEngine.isEmbeddedAppExecutable("/Applications/Python.app/Contents/MacOS/Python"))
        #expect(!ScanEngine.isEmbeddedAppExecutable("/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python"))
        #expect(!ScanEngine.isEmbeddedAppExecutable("/project/.venv/bin/python3.12"))
    }

    @Test func containerPortsBelongToTheirContainerNeverTheRuntime() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.listen(500, port: 6379)
        f.listen(500, port: 8222) // the runtime's own port, with no container behind it
        f.container("shop-db-1", image: "postgres:16-alpine", ports: [5432], memory: 300, service: "db")
        f.container("cache", image: "redis:7-alpine", ports: [6379], memory: 50)
        let rows = f.scan()
        #expect(rows.map(\.port) == [5432, 6379])
        #expect(rows.map { $0.container?.name } == ["shop-db-1", "cache"])
        #expect(rows.map(\.memory) == [300, 50])
        #expect(rows.map(\.listTitle) == ["db", "cache"])
        #expect(rows[0].cwd == NSTemporaryDirectory())
        #expect(rows.allSatisfy { $0.isProtected }, "postgres and redis images match the default protected list")
        #expect(f.containerQueries == [[.orbStack()]], "Only runtimes whose helper holds a port are asked, once per scan")
    }

    @Test func portsShareOneContainer() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 8000)
        f.listen(500, port: 8001)
        f.container("api", image: "ghcr.io/acme/api:1.2", ports: [8000, 8001], memory: 400, cpu: 50)
        let rows = f.scan()
        #expect(rows.map(\.cpu) == [50, 50])
        #expect(!rows[0].isProtected)
        let resources = ServerResources(rows)
        #expect(resources.memory == 400)
        #expect(resources.memoryByPort == [8000: 200, 8001: 200])
    }

    @Test func aRuntimesOwnPortsDoNotKeepItWatched() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 8222) // OrbStack's own SSH server
        f.runtimes[.orbStack()] = RuntimeSnapshot(listedAt: f.epoch.addingTimeInterval(ScanEngine.ownPortSettle))
        #expect(f.scan().isEmpty)
        #expect(f.containerQueries == [[.orbStack()]], "Asked once, to learn the port has no container")
        _ = f.scan(after: 2)
        #expect(f.containerQueries.count == 1, "Its own port alone no longer keeps the engine watched")
        // A container port brings it back.
        f.listen(500, port: 5432)
        f.container("db", image: "postgres", ports: [5432])
        #expect(f.scan(after: 4).map(\.port) == [5432])
        #expect(f.containerQueries.count == 2)
        // A freed own port is forgotten, so a container can take it later.
        f.sockets = SocketScan()
        f.listen(500, port: 5432)
        _ = f.scan(after: 6)
        f.listen(500, port: 8222)
        f.container("web", image: "web", ports: [8222])
        #expect(f.scan(after: 8).map(\.port).sorted() == [5432, 8222])
    }

    @Test func aListFromBeforeThePortAppearedCannotMakeItTheRuntimes() {
        // A runtime binds a container's port just before listing the container.
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.runtimes[.orbStack()] = RuntimeSnapshot(listedAt: f.epoch)
        #expect(f.scan().isEmpty)
        _ = f.scan(after: 2)
        #expect(f.containerQueries.count == 2, "Still watched, since the list predates the port")
        f.container("db", image: "postgres", ports: [5432])
        #expect(f.scan(after: 4).map(\.port) == [5432])
    }

    @Test func aFailedListNeverMakesPortsTheRuntimes() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        // The engine answered once, then stopped, with the helper still holding the port.
        f.runtimes[.orbStack()] = RuntimeSnapshot(listedAt: f.epoch.addingTimeInterval(60), listFailing: true)
        #expect(f.scan().isEmpty)
        #expect(f.scan(after: 2).isEmpty)
        #expect(f.containerQueries.count == 2, "Still watched, so the rows come back with the engine")
        f.runtimes = [:]
        f.container("db", image: "postgres", ports: [5432])
        #expect(f.scan(after: 4).map(\.port) == [5432])
    }

    @Test func pausedContainersComeFromTheEngineAndNeverSignalAPid() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 8000)
        f.container("api", image: "api", ports: [8000])
        f.runtimes[.orbStack()]!.containers[0].isPaused = true
        let row = f.scan()[0]
        #expect(row.isPaused)
        #expect(row.pauseTargets.isEmpty)
        #expect(row.status(alertThreshold: 1 << 40) == .paused)
    }

    @Test func containersNeverReadAsIdle() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.container("db", image: "postgres", ports: [5432])
        var row = f.scan()[0]
        row.lastActive = Date().addingTimeInterval(-86_400)
        #expect(!row.isIdle)
        #expect(row.status(alertThreshold: 1 << 40) == .running)
    }

    @Test func sectionsPutNativeServersFirstThenGroupContainers() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.process(20)
        f.listen(20, port: 7000)
        f.listen(500, port: 3306)
        f.listen(500, port: 5432)
        f.listen(500, port: 8081)
        f.container("db", image: "postgres", ports: [5432], memory: 100, service: "db")
        f.container("mysql", image: "mysql", ports: [3306], memory: 900, service: "mysql")
        f.runtimes[.orbStack()]!.containers[1] = ContainerInfo(id: "mysql-id", name: "crm-mysql-1", image: "mysql", runtime: .orbStack(),
                                                              publishedPorts: [3306], composeProject: "crm", composeService: "mysql")
        f.container("quirky_turing", image: "nginx", ports: [8081], memory: 50)
        let rows = f.scan()

        let byPort = ServerSection.arrange(ServerSort.port.sorted(rows), sort: .port)
        #expect(byPort.map(\.title) == [nil, "crm", "shop", "OrbStack"])
        #expect(byPort.map { $0.servers.map(\.port) } == [[7000], [3306], [5432], [8081]])
        #expect(byPort[1].detail == "OrbStack")
        #expect(byPort[3].detail == nil)
        #expect(byPort[3].servers[0].listTitle == "quirky_turing")

        let byUsage = ServerSection.arrange(ServerSort.usage.sorted(rows), sort: .usage)
        #expect(byUsage.map(\.title) == [nil, "crm", "shop", "OrbStack"], "Groups stay whole, largest first")

        let held = ServerSection.arrange(rows.reversed(), sort: nil)
        #expect(held.map(\.title) == [nil, "OrbStack", "shop", "crm"], "Without a sort, groups keep the order given")
    }

    @Test func runtimesWithoutOrbStacksAppStillSubtractTheirContainers() {
        let f = Fixture()
        let rancher = ContainerRuntime.owning(executablePath: "/usr/bin/ssh", arguments: ["ssh", "-S", "/Users/me/Library/Application Support/rancher-desktop/lima/0/ssh.sock"], home: "/Users/me")!
        let colima = ContainerRuntime.owning(executablePath: "/usr/bin/ssh", arguments: ["ssh: /Users/me/.colima/_lima/colima/ssh.sock [mux]"], home: "/Users/me")!
        #expect(rancher.appBundle == "Rancher Desktop.app")
        func row(_ runtime: ContainerRuntime, id: String, memory: UInt64, port: Int) -> Server {
            f.orbStackHelper(500)
            f.listen(500, port: port)
            f.runtimes = [:]
            f.container(id, image: "api", ports: [port], memory: memory)
            var server = f.scan().first { $0.port == port }!
            server.container = ContainerInfo(id: id, name: id, image: "api", runtime: runtime, publishedPorts: [port])
            return server
        }
        let rows = [row(rancher, id: "a", memory: 300, port: 8000), row(colima, id: "b", memory: 200, port: 8001)]
        let apps = [AppMemory(id: "/Applications/Rancher Desktop.app", name: "Rancher Desktop", bundlePath: "/Applications/Rancher Desktop.app", agent: nil, memory: 1000),
                    AppMemory(id: "qemu-system-aarch", name: "qemu-system-aarch", bundlePath: nil, agent: nil, memory: 900),
                    AppMemory(id: "limactl", name: "limactl", bundlePath: nil, agent: nil, memory: 50),
                    AppMemory(id: "node", name: "node", bundlePath: nil, agent: nil, memory: 40)]
        let adjusted = Dictionary(uniqueKeysWithValues: AppUsageScanner.excludingContainers(apps, servers: rows).map { ($0.id, $0.memory) })
        #expect(adjusted["/Applications/Rancher Desktop.app"] == 700)
        #expect(adjusted["qemu-system-aarch"] == 700, "Only the largest process that could be the VM")
        #expect(adjusted["limactl"] == 50)
        #expect(adjusted["node"] == 40)
    }

    @Test func containerRowsNeverCarryPidsToSignal() {
        // Stop signals `processStarts`. For a container that would be the
        // runtime's helper, so every container row must leave it empty.
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.listen(500, port: 8000)
        f.container("db", image: "postgres", ports: [5432])
        f.container("api", image: "api", ports: [8000], memory: nil)
        for seconds in [0.0, 2, 4] {
            let rows = f.scan(after: seconds)
            #expect(rows.count == 2)
            #expect(rows.allSatisfy { $0.processStarts.isEmpty && $0.processes.isEmpty })
        }
    }

    @Test func historyRecordsEachStatsSampleOnceAndNeverAMissingOne() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.container("db", image: "postgres", ports: [5432], memory: nil)
        var row = f.scan()[0]
        #expect(row.history.isEmpty, "No sample yet is no data, not 0 MB")
        f.sample("db", memory: 900_000_000)
        row = f.scan(after: 1)[0]
        row = f.scan(after: 2)[0]
        #expect(row.history.map(\.memory) == [900_000_000], "A sample is recorded once, however many scans read it")
        f.sample("db", memory: 900_000_000, after: 150)
        row = f.scan(after: 150)[0]
        #expect(row.history.count == 2)
        #expect(row.memoryGrowth == 0 && !row.isLeaking(), "A flat container never reads as a leak")
    }

    @Test func composeFolderInsideALinuxVMIsNotStale() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 3000)
        f.container("web", image: "web", ports: [3000], service: "web", workingDirectory: "/home/me/app")
        let row = f.scan()[0]
        #expect(row.cwd == nil)
        #expect(row.cwdExists)
        #expect(ServerMonitor.cleanUpReason(for: row, mode: .automatic, idleThreshold: 0, longRunningThreshold: 0, deletedWorktree: true) == nil)
    }

    @Test func containersAreOnlySuggestedForCleanUpWhenLeaking() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 8000)
        f.container("api", image: "api", ports: [8000], memory: 100_000_000)
        // Idle for hours with no host-side connections: it may still be serving its compose network.
        var row = f.scan()[0]
        row.lastActive = f.epoch.addingTimeInterval(-86_400)
        #expect(ServerMonitor.cleanUpReason(for: row, mode: .automatic, idleThreshold: 60, longRunningThreshold: 60, deletedWorktree: true) == nil)
        f.sample("api", memory: 900_000_000, after: 150)
        row = f.scan(after: 150)[0]
        #expect(ServerMonitor.cleanUpReason(for: row, mode: .ask, idleThreshold: 60, longRunningThreshold: 60, deletedWorktree: true)?.isLeak == true)
        #expect(row.getsAlerts)
    }

    @Test func protectedContainersStillGetMemoryAlerts() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.container("db", image: "pgvector/pgvector:pg16", ports: [5432])
        f.process(20, name: "postgres")
        f.listen(20, port: 5433)
        f.config.allowlist.insert("postgres")
        f.config.protected = ["postgres"]
        let rows = f.scan()
        #expect(rows.map(\.isProtected) == [true, true])
        #expect(rows.map(\.getsAlerts) == [true, false], "Native databases stay quiet; containers still warn")
    }

    @Test func containersOnOnePortKeepSeparateIdentities() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.container("old-db", image: "postgres", ports: [5432])
        let before = f.scan()
        f.runtimes = [:]
        f.container("new-db", image: "postgres", ports: [5432])
        let after = f.scan(after: 2)
        #expect(before[0].rootPid == after[0].rootPid, "Both rows sit behind the same helper")
        #expect(before[0].identityKey != after[0].identityKey)
        #expect(after[0].history.count == 1, "The replacement starts its own history")
        f.process(20)
        f.listen(20, port: 3000)
        #expect(f.scan(after: 4).first { $0.port == 3000 }?.identityKey == "3000-20")
    }

    @Test func turningContainersOffHidesTheRuntimeHelper() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.container("db", image: "postgres", ports: [5432])
        f.config.showContainers = false
        f.config.allowlist.insert("OrbStack Helper")
        #expect(f.scan().isEmpty)
        #expect(f.containerQueries.isEmpty)
    }

    @Test func runtimeAppMemoryExcludesItsContainers() {
        let f = Fixture()
        f.orbStackHelper(500)
        f.listen(500, port: 5432)
        f.listen(500, port: 5433)
        f.container("db", image: "postgres", ports: [5432, 5433], memory: 300)
        let rows = f.scan()
        let apps = [AppMemory(id: "/Applications/OrbStack.app", name: "OrbStack", bundlePath: "/Applications/OrbStack.app", agent: nil, memory: 1000),
                    AppMemory(id: "/Applications/Safari.app", name: "Safari", bundlePath: "/Applications/Safari.app", agent: nil, memory: 800)]
        let adjusted = AppUsageScanner.excludingContainers(apps, servers: rows)
        #expect(adjusted.map(\.name) == ["Safari", "OrbStack"])
        #expect(adjusted.map(\.memory) == [800, 700])
    }

    @Test func versionedPythonNamesRespectUserAllowlist() {
        #expect(ScanEngine.isAllowed("python3.14", allowlist: ["python3"]))
        #expect(ScanEngine.isAllowed("Python", allowlist: ["Python"]))
        #expect(!ScanEngine.isAllowed("python3.14", allowlist: ["node"]))
        #expect(!ScanEngine.isAllowed("python3.helper", allowlist: ["python3"]))
        #expect(!ScanEngine.isAllowed("python3.", allowlist: ["python3"]))
    }
}
