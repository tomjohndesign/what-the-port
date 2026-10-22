import Darwin
import Foundation

/// A container runtime on this Mac: a helper process that holds the ports
/// containers publish, and the Docker Engine API socket that knows which
/// container owns each port. Stopping the helper would take every container
/// down with it, so container rows never signal it.
struct ContainerRuntime: Hashable {
    /// Shown on container rows: OrbStack, Docker, Colima, Rancher Desktop.
    let name: String
    let socketPath: String
    /// The app whose own memory already includes its containers' VM.
    var appBundle: String?

    static func orbStack(home: String = Self.home) -> ContainerRuntime {
        ContainerRuntime(name: "OrbStack", socketPath: home + "/.orbstack/run/docker.sock", appBundle: "OrbStack.app")
    }

    static func dockerDesktop(home: String = Self.home) -> ContainerRuntime {
        ContainerRuntime(name: "Docker", socketPath: home + "/.docker/run/docker.sock", appBundle: "Docker.app")
    }

    /// Recognises a runtime's port helper. OrbStack and Docker Desktop are found
    /// by executable, since the kernel truncates names like `com.docker.backend`.
    /// Colima and Rancher Desktop forward ports through Lima, with `ssh` or
    /// `limactl hostagent` processes whose arguments name the Lima instance;
    /// a plain `ssh` tunnel never matches.
    static func owning(executablePath path: String, arguments: [String], home: String = Self.home) -> ContainerRuntime? {
        if path.contains("/OrbStack.app/") { return .orbStack(home: home) }
        if path.contains("/Docker.app/") { return .dockerDesktop(home: home) }
        let tool = (path as NSString).lastPathComponent
        guard tool == "ssh" || tool == "limactl" else { return nil }
        let joined = arguments.joined(separator: " ")
        if let range = joined.range(of: "/.colima/_lima/") {
            // Lima instance `colima` is Colima's default profile, `colima-work` is profile `work`.
            let instance = joined[range.upperBound...].prefix { $0 != "/" && $0 != " " }
            let profile = instance == "colima" ? "default" : String(instance.dropFirst("colima-".count))
            guard instance.hasPrefix("colima"), !profile.isEmpty else { return nil }
            let name = profile == "default" ? "Colima" : "Colima \(profile)"
            return ContainerRuntime(name: name, socketPath: home + "/.colima/\(profile)/docker.sock")
        }
        if joined.contains("/rancher-desktop/lima/") {
            return ContainerRuntime(name: "Rancher Desktop", socketPath: home + "/.rd/docker.sock")
        }
        return nil
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path
}

/// A running container with at least one TCP port published on the Mac.
struct ContainerInfo: Equatable {
    let id: String
    let name: String
    let image: String
    let runtime: ContainerRuntime
    let publishedPorts: Set<Int>
    var composeProject: String?
    var composeService: String?
    /// The folder `docker compose` ran in, from the container's labels. It can
    /// be a path inside a Linux VM that doesn't exist on the Mac.
    var workingDirectory: String?

    var shortID: String { String(id.prefix(12)) }

    /// `postgres:16-alpine` → `postgres`, `ghcr.io/saleor/saleor:3.22` → `saleor`.
    var imageName: String {
        let path = image.split(separator: "@").first.map(String.init) ?? image
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.split(separator: ":").first.map(String.init) ?? last
    }

    /// Image names that hold data, matched anywhere in the image's repository
    /// so `pgvector/pgvector`, `postgis/postgis`, `bitnami/postgresql` and
    /// `redis/redis-stack` count too.
    static let dataStores = ["postgres", "postgis", "pgvector", "timescale", "redis", "valkey", "keydb",
                             "mysql", "mariadb", "mongo", "mssql", "couchdb", "cassandra", "clickhouse", "neo4j"]

    /// Databases are protected from Clean up, like the native ones. An image
    /// whose name is on the protected process list counts too.
    func isProtected(by names: Set<String>) -> Bool {
        let repository = (image.split(separator: "@").first.map(String.init) ?? image)
            .split(separator: "/").map { $0.split(separator: ":").first.map(String.init) ?? String($0) }
            .joined(separator: "/").lowercased()
        return Self.dataStores.contains(where: repository.contains) || names.contains(imageName.lowercased())
    }
}

/// Cumulative usage, in the same units the process inspector reports.
struct ContainerUsage: Equatable {
    let memory: UInt64
    let cpuNanoseconds: UInt64
}

/// A minimal Docker Engine API client over the runtime's unix socket. Menu bar
/// apps don't get the shell's PATH, so this avoids depending on the CLI.
enum DockerEngine {
    static func containers(_ runtime: ContainerRuntime) -> [ContainerInfo]? {
        guard let body = request("GET", "/containers/json", runtime: runtime),
              let list = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return nil }
        return list.compactMap { parseContainer($0, runtime: runtime) }
    }

    static func usage(_ id: String, runtime: ContainerRuntime) -> ContainerUsage? {
        guard let body = request("GET", "/containers/\(id)/stats?stream=false&one-shot=true", runtime: runtime),
              let stats = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return parseUsage(stats)
    }

    static func startedAt(_ id: String, runtime: ContainerRuntime) -> Date? {
        guard let body = request("GET", "/containers/\(id)/json", runtime: runtime),
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let state = json["State"] as? [String: Any],
              let started = state["StartedAt"] as? String else { return nil }
        return parseDate(started)
    }

    /// `docker stop`: SIGTERM, then SIGKILL after the container's own timeout.
    static func stop(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) {
        post("/containers/\(container.id)/stop", runtime: container.runtime, completion: completion)
    }

    static func restart(_ container: ContainerInfo, completion: ((Bool) -> Void)? = nil) {
        post("/containers/\(container.id)/restart", runtime: container.runtime, completion: completion)
    }

    private static func post(_ path: String, runtime: ContainerRuntime, completion: ((Bool) -> Void)?) {
        DispatchQueue.global().async {
            // Stop waits for the container to exit, up to its stop timeout.
            let ok = request("POST", path, runtime: runtime, timeout: 60) != nil
            if let completion { DispatchQueue.main.async { completion(ok) } }
        }
    }

    // MARK: - Parsing

    static func parseContainer(_ json: [String: Any], runtime: ContainerRuntime) -> ContainerInfo? {
        guard let id = json["Id"] as? String else { return nil }
        let ports = (json["Ports"] as? [[String: Any]] ?? []).compactMap { port -> Int? in
            guard (port["Type"] as? String) == "tcp" else { return nil }
            return port["PublicPort"] as? Int
        }
        guard !ports.isEmpty else { return nil }
        let names = json["Names"] as? [String] ?? []
        let name = names.first.map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 } ?? String(id.prefix(12))
        let labels = json["Labels"] as? [String: String] ?? [:]
        return ContainerInfo(id: id, name: name, image: json["Image"] as? String ?? "", runtime: runtime,
                             publishedPorts: Set(ports),
                             composeProject: labels["com.docker.compose.project"],
                             composeService: labels["com.docker.compose.service"],
                             workingDirectory: labels["com.docker.compose.project.working_dir"])
    }

    /// Memory as `docker stats` counts it: usage minus reclaimable page cache.
    static func parseUsage(_ stats: [String: Any]) -> ContainerUsage? {
        guard let memory = stats["memory_stats"] as? [String: Any],
              let used = (memory["usage"] as? NSNumber)?.uint64Value,
              let cpu = stats["cpu_stats"] as? [String: Any],
              let total = ((cpu["cpu_usage"] as? [String: Any])?["total_usage"] as? NSNumber)?.uint64Value else { return nil }
        let details = memory["stats"] as? [String: Any] ?? [:]
        let cache = ((details["inactive_file"] ?? details["total_inactive_file"]) as? NSNumber)?.uint64Value ?? 0
        return ContainerUsage(memory: used > cache ? used - cache : used, cpuNanoseconds: total)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    // MARK: - HTTP over a unix socket

    /// Returns the response body for a 2xx status, otherwise nil.
    static func request(_ method: String, _ path: String, runtime: ContainerRuntime, timeout: Int = 2) -> Data? {
        let fd = send(method, path, runtime: runtime, timeout: timeout)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            response.append(buffer, count: count)
        }
        return parseResponse(response)
    }

    /// Opens a long-lived GET, such as the event stream, with no read timeout.
    /// The caller reads it and closes the returned socket.
    static func openStream(_ path: String, runtime: ContainerRuntime) -> Int32 {
        send("GET", path, runtime: runtime, timeout: 2, readTimeout: 0)
    }

    /// Connects to the runtime's socket and sends an HTTP/1.0 request, so the
    /// engine answers without chunking and closes when it's done.
    private static func send(_ method: String, _ path: String, runtime: ContainerRuntime, timeout: Int, readTimeout: Int? = nil) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        var sendTime = timeval(tv_sec: timeout, tv_usec: 0)
        var readTime = timeval(tv_sec: readTimeout ?? timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTime, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTime, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(runtime.socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
            buffer[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        let message = "\(method) \(path) HTTP/1.0\r\nHost: docker\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        let sent = connected == 0 ? message.utf8CString.withUnsafeBufferPointer { Darwin.send(fd, $0.baseAddress, $0.count - 1, 0) } : -1
        guard sent == message.utf8.count else { close(fd); return -1 }
        return fd
    }

    /// Container events that change which containers are running.
    static let listChangingActions: Set<String> = ["start", "restart", "die", "stop", "kill", "destroy", "pause", "unpause"]

    static func parseEvent(_ line: Data) -> (action: String, id: String, time: Date)? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let action = json["Action"] as? String ?? json["status"] as? String,
              let id = (json["Actor"] as? [String: Any])?["ID"] as? String ?? json["id"] as? String else { return nil }
        let time = (json["time"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? Date()
        return (action, id, time)
    }

    static func parseResponse(_ response: Data) -> Data? {
        guard let split = response.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: response[..<split.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let status = lines.first?.split(separator: " ").dropFirst().first.flatMap { Int($0) } ?? 0
        guard (200..<300).contains(status) else { return nil }
        let body = response[split.upperBound...]
        let chunked = lines.contains { $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked") }
        return chunked ? dechunk(Data(body)) : Data(body)
    }

    private static func dechunk(_ data: Data) -> Data {
        var result = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while let line = data.range(of: crlf, in: index..<data.endIndex),
              let sizeText = String(data: data[index..<line.lowerBound], encoding: .ascii),
              let size = Int(sizeText.split(separator: ";").first ?? "", radix: 16), size > 0 {
            let start = line.upperBound
            let end = data.index(start, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            result.append(data[start..<end])
            index = data.index(end, offsetBy: 2, limitedBy: data.endIndex) ?? data.endIndex
        }
        return result
    }
}
