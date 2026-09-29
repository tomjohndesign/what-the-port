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
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        var config = ScanConfig(minPort: 3000, maxPort: 9999, allowlist: ["node", "Python", "python3"],
                                linkClaude: false, linkCodex: false, linkConductor: false, showBranches: false)
        lazy var engine = ScanEngine(inspector: .init(
            usage: { [unowned self] pid in
                reads[pid, default: 0] += 1
                return usages[pid]
            },
            arguments: { [unowned self] in arguments[$0] },
            currentDirectory: { _ in NSTemporaryDirectory() }
        ))

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

    @Test func versionedPythonNamesRespectUserAllowlist() {
        #expect(ScanEngine.isAllowed("python3.14", allowlist: ["python3"]))
        #expect(ScanEngine.isAllowed("Python", allowlist: ["Python"]))
        #expect(!ScanEngine.isAllowed("python3.14", allowlist: ["node"]))
        #expect(!ScanEngine.isAllowed("python3.helper", allowlist: ["python3"]))
        #expect(!ScanEngine.isAllowed("python3.", allowlist: ["python3"]))
    }
}
