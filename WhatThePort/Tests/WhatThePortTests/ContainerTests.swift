import Foundation
import Testing
@testable import WhatThePort

struct ContainerTests {
    @Test func runtimeHelpersAreRecognisedButPlainTunnelsAreNot() {
        let home = "/Users/me"
        func runtime(_ path: String, _ arguments: [String] = []) -> ContainerRuntime? {
            ContainerRuntime.owning(executablePath: path, arguments: arguments, home: home)
        }
        #expect(runtime("/Applications/OrbStack.app/Contents/Frameworks/OrbStack Helper.app/Contents/MacOS/OrbStack Helper")
            == .orbStack(home: home))
        #expect(runtime("/Applications/Docker.app/Contents/MacOS/com.docker.backend")?.socketPath == "/Users/me/.docker/run/docker.sock")
        // Colima forwards ports through Lima's shared ssh connection or its host agent.
        let colima = runtime("/usr/bin/ssh", ["ssh: /Users/me/.colima/_lima/colima/ssh.sock [mux]"])
        #expect(colima?.name == "Colima")
        #expect(colima?.socketPath == "/Users/me/.colima/default/docker.sock")
        #expect(colima?.appBundle == nil)
        #expect(runtime("/usr/bin/ssh", ["ssh: /Users/me/.colima/_lima/colima-work/ssh.sock [mux]"])?.socketPath
            == "/Users/me/.colima/work/docker.sock")
        #expect(runtime("/opt/homebrew/bin/limactl", ["limactl", "hostagent", "--pidfile", "/Users/me/.colima/_lima/colima/ha.pid"])?.name == "Colima")
        #expect(runtime("/usr/bin/ssh", ["ssh", "-S", "/Users/me/Library/Application Support/rancher-desktop/lima/0/ssh.sock"])?.socketPath
            == "/Users/me/.rd/docker.sock")
        // Someone's own tunnel, or a non-container Lima VM, isn't a runtime.
        #expect(runtime("/usr/bin/ssh", ["ssh", "-L", "5432:db:5432", "bastion"]) == nil)
        #expect(runtime("/usr/bin/ssh", ["ssh: /Users/me/.lima/default/ssh.sock [mux]"]) == nil)
        #expect(runtime("/opt/homebrew/bin/node", ["node", "/Users/me/.colima/_lima/colima/x.js"]) == nil)
    }

    @Test func containerListKeepsPublishedTCPPortsAndComposeLabels() {
        let json: [String: Any] = [
            "Id": "25dff7df533f0123",
            "Names": ["/shop-db-1"],
            "Image": "postgres:16-alpine",
            "Ports": [
                ["IP": "0.0.0.0", "PrivatePort": 5432, "PublicPort": 5433, "Type": "tcp"],
                ["IP": "::", "PrivatePort": 5432, "PublicPort": 5433, "Type": "tcp"],
                ["PrivatePort": 9000, "Type": "tcp"],
                ["IP": "0.0.0.0", "PrivatePort": 53, "PublicPort": 5353, "Type": "udp"],
            ],
            "Labels": [
                "com.docker.compose.project": "shop",
                "com.docker.compose.service": "db",
                "com.docker.compose.project.working_dir": "/Users/me/shop",
            ],
        ]
        let container = DockerEngine.parseContainer(json, runtime: .orbStack())
        #expect(container?.name == "shop-db-1")
        #expect(container?.publishedPorts == [5433])
        #expect(container?.composeService == "db")
        #expect(container?.workingDirectory == "/Users/me/shop")
        #expect(container?.shortID == "25dff7df533f")

        var unpublished = json
        unpublished["Ports"] = [["PrivatePort": 5432, "Type": "tcp"]]
        #expect(DockerEngine.parseContainer(unpublished, runtime: .orbStack()) == nil)
    }

    @Test func memoryExcludesReclaimablePageCacheLikeDockerStats() {
        let cgroupV2: [String: Any] = [
            "memory_stats": ["usage": 1_339_572_224, "stats": ["inactive_file": 7_897_088]],
            "cpu_stats": ["cpu_usage": ["total_usage": 43_018_077_000]],
        ]
        #expect(DockerEngine.parseUsage(cgroupV2) == ContainerUsage(memory: 1_331_675_136, cpuNanoseconds: 43_018_077_000))
        let cgroupV1: [String: Any] = [
            "memory_stats": ["usage": 1000, "stats": ["total_inactive_file": 200]],
            "cpu_stats": ["cpu_usage": ["total_usage": 5]],
        ]
        #expect(DockerEngine.parseUsage(cgroupV1)?.memory == 800)
        #expect(DockerEngine.parseUsage(["memory_stats": [:], "cpu_stats": [:]]) == nil)
    }

    @Test func responsesAreReadWithAndWithoutChunking() {
        let plain = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n[]".utf8)
        #expect(DockerEngine.parseResponse(plain) == Data("[]".utf8))
        let chunked = Data("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\n[{\"a\r\n4\r\n\":1}\r\n1\r\n]\r\n0\r\n\r\n".utf8)
        #expect(DockerEngine.parseResponse(chunked) == Data("[{\"a\":1}]".utf8))
        let stopped = Data("HTTP/1.1 304 Not Modified\r\n\r\n".utf8)
        #expect(DockerEngine.parseResponse(stopped) == nil)
        let missing = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 2\r\n\r\n{}".utf8)
        #expect(DockerEngine.parseResponse(missing) == nil)
    }

    @Test func databaseImagesAreProtectedWhateverTheirRepository() {
        func protected(_ image: String, _ names: Set<String> = Set(Preferences.defaultProtected)) -> Bool {
            ContainerInfo(id: "id", name: "n", image: image, runtime: .dockerDesktop(), publishedPorts: [1]).isProtected(by: names)
        }
        for image in ["postgres:16", "pgvector/pgvector:pg16", "postgis/postgis:16-3.4", "bitnami/postgresql:16",
                      "timescale/timescaledb:latest-pg16", "mariadb:11", "mysql:8", "redis/redis-stack:latest",
                      "valkey/valkey:8.1-alpine", "mongo:7", "mcr.microsoft.com/mssql/server:2022-latest",
                      "docker.io/library/postgres@sha256:abc"] {
            #expect(protected(image), "\(image)")
        }
        #expect(!protected("ghcr.io/saleor/saleor:3.22"))
        #expect(!protected("nginx:alpine"))
        // A registry port isn't part of the name.
        #expect(!protected("localhost:5432/team/api:dev"))
        #expect(protected("acme/queue:1", ["queue"]), "Images named on the protected list count too")
    }

    @Test func eventsAreParsedForContainerChanges() {
        let line = Data(#"{"status":"start","id":"abc","Type":"container","Action":"start","Actor":{"ID":"abc","Attributes":{"name":"db"}},"time":1792678187}"#.utf8)
        let event = DockerEngine.parseEvent(line)
        #expect(event?.action == "start")
        #expect(event?.id == "abc")
        #expect(event?.time == Date(timeIntervalSince1970: 1_792_678_187))
        #expect(DockerEngine.listChangingActions.isSuperset(of: ["start", "restart", "die", "destroy"]))
        #expect(!DockerEngine.listChangingActions.contains("exec_start: sh"))
    }

    @Test func aFailedListKeepsTheLastContainersForAGracePeriod() {
        let now = Date(timeIntervalSince1970: 1_000)
        let db = ContainerInfo(id: "db", name: "db", image: "postgres", runtime: .orbStack(), publishedPorts: [5432])
        var result = RuntimeWatcher.containers(after: nil, previous: [db], failingSince: nil, now: now)
        #expect(result.containers == [db])
        result = RuntimeWatcher.containers(after: nil, previous: result.containers, failingSince: result.failingSince, now: now + 9)
        #expect(result.containers == [db], "Still within the grace period")
        result = RuntimeWatcher.containers(after: nil, previous: result.containers, failingSince: result.failingSince, now: now + 11)
        #expect(result.containers.isEmpty)
        result = RuntimeWatcher.containers(after: [db], previous: [], failingSince: result.failingSince, now: now + 12)
        #expect(result.containers == [db] && result.failingSince == nil)
    }
}
