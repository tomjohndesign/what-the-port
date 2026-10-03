import Foundation
import Testing
@testable import WhatThePort

struct ScanEngineTests {
    private final class Fixture {
        var processes: [pid_t: ProcSnapshot] = [:]
        var sockets = SocketScan()
        var usages: [pid_t: ProcUsage] = [:]
        var arguments: [pid_t: ProcArgs] = [:]
        var directories: [pid_t: String] = [:]
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
            currentDirectory: { [unowned self] in directories[$0] ?? NSTemporaryDirectory() }
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

    @Test func copilotWrapperAttributesTheExactInheritedSession() {
        let f = Fixture()
        f.process(10, name: "zsh")
        f.arguments[10] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh", "-lc", "ghcp"],
            environment: ["COPILOT_AGENT_SESSION_ID": "c0a8012e-0000-4000-8000-000000000043"]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)

        let server = f.scan()[0]

        #expect(server.agent?.kind.rawValue == "Copilot")
        #expect(server.agent?.id == "c0a8012e-0000-4000-8000-000000000043")
    }

    @Test func copilotRequiresAnExactEnabledSessionIdentity() {
        let f = Fixture()
        f.process(20)
        f.arguments[20] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "server.js"],
            environment: ["COPILOT_AGENT_SESSION_ID": "not-a-session-id"]
        )
        f.listen(20, port: 3000)
        #expect(f.scan()[0].agent == nil)

        f.arguments[20] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "server.js"],
            environment: ["COPILOT_AGENT_SESSION_ID": "c0a8012e-0000-4000-8000-000000000043"]
        )
        f.config.linkCopilot = false
        let server = f.scan()[0]
        #expect(server.agent == nil)
        #expect(server.port == 3000)
    }

    @Test func scannerKeepsRawRestartInputsPrivateFromDefaultOutput() {
        let f = Fixture()
        let arguments = ["node", "server.js", "--api-key=wtp-test-argv-secret-43"]
        let environment = ["WTP_TEST_ENV_SECRET_43": "wtp-test-env-secret-43"]
        f.process(20)
        f.arguments[20] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: arguments,
            environment: environment
        )
        f.listen(20, port: 3000)

        let server = f.scan()[0]

        #expect(server.command == "node")
        #expect(server.displayedCommand(showFull: false) == "node")
        #expect(server.processes.map(\.name) == ["node"])
        #expect(server.processes.map { $0.displayedName(showFull: false) } == ["node"])
        #expect(server.processes.map { $0.displayedName(showFull: true) } == ["node server.js --api-key=wtp-test-argv-secret-43"])
        #expect(server.displayedCommand(showFull: true) == "node server.js --api-key=wtp-test-argv-secret-43")
        #expect(server.launch?.arguments == arguments)
        #expect(server.launch?.environment == environment)
    }

    @Test func copilotConflictsAcrossAncestorsAreNotAttributed() {
        let f = Fixture()
        f.process(5, name: "zsh")
        f.arguments[5] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh"],
            environment: ["COPILOT_AGENT_SESSION_ID": "11111111-1111-4111-8111-111111111111"]
        )
        f.process(10, parent: 5, name: "zsh")
        f.arguments[10] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh"],
            environment: ["COPILOT_AGENT_SESSION_ID": "22222222-2222-4222-8222-222222222222"]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)

        #expect(f.scan()[0].agent == nil)
    }

    @Test func recognizedCopilotLauncherBoundsInheritedEnvironment() {
        let f = Fixture()
        f.process(5, name: "zsh")
        f.arguments[5] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh"],
            environment: ["COPILOT_AGENT_SESSION_ID": "11111111-1111-4111-8111-111111111111"]
        )
        f.process(10, parent: 5, name: "node")
        f.arguments[10] = ProcArgs(
            executablePath: "/node_modules/@github/copilot-darwin-arm64/bin/copilot",
            arguments: ["copilot"],
            environment: ["COPILOT_AGENT_SESSION_ID": "22222222-2222-4222-8222-222222222222"]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)

        #expect(f.scan()[0].agent?.id == "22222222-2222-4222-8222-222222222222")
    }

    @Test func ambiguousCopilotAncestrySuppressesCodexFallback() {
        let f = Fixture()
        f.process(5, name: "zsh")
        f.arguments[5] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh"],
            environment: ["COPILOT_AGENT_SESSION_ID": "11111111-1111-4111-8111-111111111111"]
        )
        f.process(10, parent: 5, name: "zsh")
        f.arguments[10] = ProcArgs(
            executablePath: "/bin/zsh",
            arguments: ["zsh"],
            environment: ["COPILOT_AGENT_SESSION_ID": "22222222-2222-4222-8222-222222222222"]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)

        #expect(f.scan()[0].agent == nil)
    }

    @Test func fullCommandPreservesEveryArgumentBoundary() {
        let f = Fixture()
        let arguments = ["node", "script with spaces", "", " leading ", "quote'arg"]
        f.process(20)
        f.arguments[20] = ProcArgs(executablePath: "/usr/local/bin/node", arguments: arguments, environment: [:])
        f.listen(20, port: 3000)

        #expect(f.scan()[0].displayedCommand(showFull: true) == "node 'script with spaces' '' ' leading ' 'quote'\\''arg'")
    }

    @Test func copilotPackageMarkerDoesNotMatchAnArbitraryArgument() {
        let f = Fixture()
        f.process(10)
        f.arguments[10] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "--label=@github/copilot"],
            environment: [:]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)

        #expect(f.scan()[0].rootPid == 10)
    }

    @Test func copilotPackageMarkerRequiresAdjacentPackageComponents() {
        let f = Fixture()
        f.process(10)
        f.arguments[10] = ProcArgs(
            executablePath: "/node_modules/@github/unrelated/copilot/bin/copilot",
            arguments: ["copilot"],
            environment: [:]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)
        #expect(f.scan()[0].rootPid == 10)

        let recognized = Fixture()
        recognized.process(10)
        recognized.arguments[10] = ProcArgs(
            executablePath: "/node_modules/@github/copilot-darwin-arm64/bin/copilot",
            arguments: ["copilot"],
            environment: [:]
        )
        recognized.process(20, parent: 10)
        recognized.listen(20, port: 3000)
        #expect(recognized.scan()[0].rootPid == 20)
    }

    @Test func nodeRuntimeFlagsStillProtectAgentScriptsWithoutMatchingEvalValues() {
        let f = Fixture()
        f.process(10)
        f.arguments[10] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "--no-warnings", "/node_modules/@anthropic-ai/claude-code/cli.js"],
            environment: [:]
        )
        f.process(20, parent: 10)
        f.listen(20, port: 3000)
        #expect(f.scan()[0].rootPid == 20)

        let eval = Fixture()
        eval.process(10)
        eval.arguments[10] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "--eval", "require('/node_modules/@github/copilot/index.js')"],
            environment: [:]
        )
        eval.process(20, parent: 10)
        eval.listen(20, port: 3000)
        #expect(eval.scan()[0].rootPid == 10)
    }

    @Test func absoluteNodeArgvZeroProtectsClaudeAndCopilotScripts() {
        let claude = Fixture()
        claude.process(10)
        claude.arguments[10] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["/usr/local/bin/node", "/node_modules/@anthropic-ai/claude-code/cli.js"],
            environment: [:]
        )
        claude.process(20, parent: 10)
        claude.listen(20, port: 3000)
        let claudeServer = claude.scan()[0]
        #expect(claudeServer.rootPid == 20)
        #expect(Set(claudeServer.processStarts.keys) == [20])

        let copilot = Fixture()
        copilot.process(10)
        copilot.arguments[10] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["/usr/local/bin/node", "--no-warnings", "/node_modules/@github/copilot-darwin-arm64/cli.js"],
            environment: [:]
        )
        copilot.process(20, parent: 10)
        copilot.arguments[20] = ProcArgs(
            executablePath: "/usr/local/bin/node",
            arguments: ["node", "server.js"],
            environment: ["COPILOT_AGENT_SESSION_ID": "c0a8012e-0000-4000-8000-000000000043"]
        )
        copilot.listen(20, port: 3000)
        let copilotServer = copilot.scan()[0]
        #expect(copilotServer.rootPid == 20)
        #expect(Set(copilotServer.processStarts.keys) == [20])
        #expect(copilotServer.agent?.id == "c0a8012e-0000-4000-8000-000000000043")
    }

    @Test func relativeAgentScriptsKeepExactSessionsAndExcludeLauncherTargets() {
        let id = "c0a8012e-0000-4000-8000-000000000043"
        for (package, filename, kind, variable) in [
            ("@github/copilot", "index.js", AgentKind.copilot, "COPILOT_AGENT_SESSION_ID"),
            ("@anthropic-ai/claude-code", "cli.js", AgentKind.claudeCode, "CLAUDE_CODE_SESSION_ID"),
        ] {
            for operand in ["node_modules/\(package)/\(filename)", "./node_modules/\(package)/\(filename)", filename, "./\(filename)"] {
                for options in [[], ["--no-warnings"], ["--require", "/helpers/preload.js"], ["--loader=/helpers/loader.js", "--import", "/helpers/import.js"]] {
                    let f = Fixture()
                    f.config.linkClaude = true
                    f.process(5, name: "zsh")
                    f.arguments[5] = ProcArgs(executablePath: "/bin/zsh", arguments: ["zsh"],
                                             environment: [variable: "11111111-1111-4111-8111-111111111111"])
                    f.process(10, parent: 5)
                    f.directories[10] = operand.contains("node_modules") ? "/inspected-project" : "/inspected-project/node_modules/\(package)"
                    f.arguments[10] = ProcArgs(executablePath: "/usr/local/bin/node",
                                              arguments: ["/usr/local/bin/node"] + options + [operand],
                                              environment: [variable: id])
                    f.process(20, parent: 10)
                    f.listen(20, port: 3000)
                    let server = f.scan()[0]
                    #expect(server.agent?.kind == kind)
                    #expect(server.agent?.id == id)
                    #expect(server.rootPid == 20)
                    #expect(Set(server.processStarts.keys) == [20])
                    #expect(server.launch?.arguments == ["node", "server.js"])
                }
            }
        }
    }

    @Test func mixedCaseCopilotAncestryKeepsCanonicalIdentityAndRawLaunchEnvironment() {
        let f = Fixture()
        let id = "c0a8012e-0000-4000-8000-000000000043"
        f.process(10)
        f.arguments[10] = ProcArgs(executablePath: "/usr/local/bin/node",
                                  arguments: ["node", "node_modules/@github/copilot/index.js"],
                                  environment: ["COPILOT_AGENT_SESSION_ID": id.lowercased()])
        f.process(20, parent: 10)
        let environment = ["COPILOT_AGENT_SESSION_ID": id.uppercased()]
        f.arguments[20] = ProcArgs(executablePath: "/usr/local/bin/node", arguments: ["node", "server.js"],
                                  environment: environment)
        f.listen(20, port: 3000)
        let server = f.scan()[0]
        #expect(server.agent?.kind == .copilot)
        #expect(server.agent?.id == id)
        #expect(server.rootPid == 20)
        #expect(Set(server.processStarts.keys) == [20])
        #expect(server.launch?.environment == environment)
    }

    @Test func invalidCopilotAncestryCannotBeOverriddenByAValidDescendant() {
        let f = Fixture()
        f.process(10, name: "zsh")
        f.arguments[10] = ProcArgs(executablePath: "/bin/zsh", arguments: ["zsh"],
                                  environment: ["COPILOT_AGENT_SESSION_ID": "invalid"])
        f.process(20, parent: 10)
        f.arguments[20] = ProcArgs(executablePath: "/usr/local/bin/node", arguments: ["node", "server.js"],
                                  environment: ["COPILOT_AGENT_SESSION_ID": "c0a8012e-0000-4000-8000-000000000043"])
        f.listen(20, port: 3000)
        #expect(f.scan()[0].agent == nil)
    }

    @Test func runtimeOptionValuesAndLaterArgumentsDoNotCreateAgentBoundaries() {
        for package in ["@github/copilot/index.js", "@anthropic-ai/claude-code/cli.js"] {
            for arguments in [
                ["node", "--eval", "node_modules/\(package)"],
                ["node", "--print=node_modules/\(package)"],
                ["node", "--require", "node_modules/\(package)", "server.js"],
                ["node", "--import=node_modules/\(package)", "server.js"],
                ["node", "--loader", "node_modules/\(package)", "server.js"],
                ["node", "server.js", "node_modules/\(package)"],
            ] {
                let f = Fixture()
                f.process(10)
                f.arguments[10] = ProcArgs(executablePath: "/usr/local/bin/node", arguments: arguments, environment: [:])
                f.process(20, parent: 10)
                f.listen(20, port: 3000)
                let server = f.scan()[0]
                #expect(server.rootPid == 10)
                #expect(Set(server.processStarts.keys) == [10, 20])
            }
        }
    }
}
