import Foundation

@MainActor
final class ServerMonitor: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var hasScanned = false
    @Published var allowlist: Set<String> = ServerMonitor.defaultAllowlist

    var minPort: Int = 3000
    var maxPort: Int = 9999

    /// Memory above which a server needs attention.
    var alertThreshold: UInt64 = 2_000_000_000
    var idleThreshold: TimeInterval = 4 * 60 * 60
    var longRunningThreshold: TimeInterval = 3 * 24 * 60 * 60

    static let defaultAllowlist: Set<String> = [
        "node", "npm", "npx", "deno", "bun",
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",
        "ruby", "rails", "puma", "unicorn",
        "php", "php-fpm",
        "java", "gradle", "mvn",
        "go", "air",
        "cargo", "rustc",
        "dotnet",
        "beam.smp", "elixir", "mix",
        "nginx", "httpd", "apache",
        "postgres", "mysql", "redis-server", "mongod",
        "docker-proxy",
    ]

    private let engine = ScanEngine()
    private let queue = DispatchQueue(label: "com.whattheport.scan", qos: .utility)
    private var timer: Timer?
    private var isScanning = false

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: "allowlist") as? [String] { allowlist = Set(saved) }
        let min = defaults.integer(forKey: "minPort")
        let max = defaults.integer(forKey: "maxPort")
        if min > 0 { minPort = min }
        if max > 0 { maxPort = max }
    }

    func start() {
        guard timer == nil else { return }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let config = ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist)
        queue.async { [engine] in
            let result = engine.scan(config)
            Task { @MainActor in
                self.servers = result
                self.hasScanned = true
                self.isScanning = false
            }
        }
    }

    /// Runs a scan synchronously. Used by snapshot mode.
    func scanNow() {
        let config = ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist)
        servers = queue.sync { engine.scan(config) }
        hasScanned = true
    }

    // MARK: - Derived

    var totalMemory: UInt64 { servers.reduce(0) { $0 + $1.memory } }
    var totalCPU: Double { servers.reduce(0) { $0 + $1.cpu } }
    var needsAttention: Bool { servers.contains { $0.status(alertThreshold: alertThreshold) == .attention } }

    func server(port: Int) -> Server? { servers.first { $0.port == port } }

    func status(of server: Server) -> ServerStatus { server.status(alertThreshold: alertThreshold) }

    func cleanUpReason(for server: Server) -> CleanUpReason? {
        guard !server.isProtected else { return nil }
        if !server.cwdExists { return .worktreeDeleted }
        if server.idleFor >= idleThreshold { return .idle(server.idleFor) }
        if let uptime = server.uptime, uptime >= longRunningThreshold { return .longRunning(uptime) }
        if server.isLeaking() { return .leaking(UInt64(max(server.memoryGrowth, 0))) }
        return nil
    }

    /// Servers worth suggesting in Clean up. Leaking ones are listed but not
    /// preselected, since they're usually still in use.
    var cleanUpCandidates: [(server: Server, reason: CleanUpReason)] {
        servers.compactMap { server in cleanUpReason(for: server).map { (server, $0) } }
    }

    var suggestedCleanUpCount: Int {
        cleanUpCandidates.filter { if case .leaking = $0.reason { return false } else { return true } }.count
    }

    // MARK: - Actions

    func stop(_ server: Server) {
        ProcessControl.stop(server) { [weak self] in self?.scan() }
        rescanSoon()
    }

    func restart(_ server: Server) {
        ProcessControl.restart(server) { [weak self] _ in self?.scan() }
    }

    private func rescanSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scan() }
    }

    // MARK: - Settings

    func addToAllowlist(_ process: String) {
        allowlist.insert(process)
        saveAllowlist()
    }

    func removeFromAllowlist(_ process: String) {
        allowlist.remove(process)
        saveAllowlist()
    }

    func resetAllowlist() {
        allowlist = Self.defaultAllowlist
        saveAllowlist()
    }

    private func saveAllowlist() {
        UserDefaults.standard.set(Array(allowlist), forKey: "allowlist")
        scan()
    }
}
