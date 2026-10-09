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
