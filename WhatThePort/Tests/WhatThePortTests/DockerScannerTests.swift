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
}
