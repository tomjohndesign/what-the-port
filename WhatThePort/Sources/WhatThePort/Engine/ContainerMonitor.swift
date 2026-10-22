import Darwin
import Foundation

/// A container's memory and CPU from one stats sample.
struct ContainerSample: Equatable {
    let memory: UInt64
    /// Share of one core since the previous sample, like a process's CPU.
    let cpu: Double
    let at: Date
}

/// What a runtime's watcher knows: running containers with published ports,
/// their latest stats and start times.
struct RuntimeSnapshot {
    /// When the engine last listed its containers; nil until the first list.
    var listedAt: Date?
    var containers: [ContainerInfo] = []
    var samples: [String: ContainerSample] = [:]
    var startedAt: [String: Date] = [:]
}

/// Keeps each runtime's containers and stats current off the scan queue, so a
/// slow or hung engine never delays a scan. A runtime is only watched while
/// its helper holds a port: scans ask for it, and the watcher stops once they
/// haven't for 10 seconds, leaving the engine and its VM alone.
final class ContainerMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var watchers: [ContainerRuntime: RuntimeWatcher] = [:]
    private var interval: TimeInterval = 5

    /// Seconds between stats samples: shorter while someone is looking.
    func setSampleInterval(_ seconds: TimeInterval) {
        lock.withLock {
            interval = max(seconds, 1)
            watchers.values.forEach { $0.sampleInterval = interval }
        }
    }

    /// The latest state for each runtime, starting a watcher for any that
    /// isn't watched yet. Never blocks on the engine.
    func snapshot(_ runtimes: Set<ContainerRuntime>, now: Date = Date()) -> [ContainerRuntime: RuntimeSnapshot] {
        lock.withLock {
            watchers = watchers.filter { !$0.value.isStopped }
            var result: [ContainerRuntime: RuntimeSnapshot] = [:]
            for runtime in runtimes {
                let watcher = watchers[runtime] ?? {
                    let watcher = RuntimeWatcher(runtime: runtime, sampleInterval: interval)
                    watchers[runtime] = watcher
                    watcher.start()
                    return watcher
                }()
                watcher.requested(at: now)
                result[runtime] = watcher.snapshot
            }
            return result
        }
    }

    /// Runtimes with a live watcher, i.e. an open event stream.
    var watchedRuntimes: Set<ContainerRuntime> {
        lock.withLock { Set(watchers.filter { !$0.value.isStopped }.keys) }
    }

    /// After Restart, the next sample refetches the start time.
    func forgetStart(of container: ContainerInfo) {
        lock.withLock { watchers[container.runtime]?.forgetStart(container.id) }
    }
}

/// One runtime's list, event stream and stats sampler.
final class RuntimeWatcher: @unchecked Sendable {
    /// How long a runtime is watched after scans stop asking for it.
    static let idleTimeout: TimeInterval = 10
    /// How long the last good container list is kept while the engine fails,
    /// so one bad response doesn't reset every row's history and alerts.
    static let listGrace: TimeInterval = 10

    let runtime: ContainerRuntime
    var sampleInterval: TimeInterval {
        get { condition.withLock { _sampleInterval } }
        set { condition.withLock { _sampleInterval = newValue; condition.signal() } }
    }

    private let condition = NSCondition()
    private var _sampleInterval: TimeInterval
    private var state = RuntimeSnapshot()
    private var lastRequest = Date()
    private var listFailingSince: Date?
    private var needsList = true
    private var stopped = false
    private var previousCPU: [String: (nanoseconds: UInt64, at: Date)] = [:]
    private var eventSocket: Int32 = -1

    init(runtime: ContainerRuntime, sampleInterval: TimeInterval) {
        self.runtime = runtime
        _sampleInterval = sampleInterval
    }

    var isStopped: Bool { condition.withLock { stopped } }
    var snapshot: RuntimeSnapshot { condition.withLock { state } }

    func requested(at date: Date) { condition.withLock { lastRequest = date } }

    func forgetStart(_ id: String) {
        condition.withLock {
            state.startedAt[id] = nil
            condition.signal()
        }
    }

    func start() {
        Thread.detachNewThread { [self] in run() }
        Thread.detachNewThread { [self] in watchEvents() }
    }

    /// A failed list keeps the previous containers for `listGrace`, so one bad
    /// response doesn't drop the rows and reset their history and alerts.
    static func containers(after listed: [ContainerInfo]?, previous: [ContainerInfo], failingSince: Date?,
                           now: Date) -> (containers: [ContainerInfo], failingSince: Date?) {
        if let listed { return (listed, nil) }
        let since = failingSince ?? now
        return (now.timeIntervalSince(since) > listGrace ? [] : previous, since)
    }

    // MARK: - Sampling loop

    private func run() {
        var nextSample = Date.distantPast
        while true {
            condition.lock()
            if stopped || Date().timeIntervalSince(lastRequest) > Self.idleTimeout {
                stop()
                condition.unlock()
                return
            }
            let listNow = needsList
            needsList = false
            condition.unlock()

            if listNow { refreshList() }
            if Date() >= nextSample {
                sample()
                nextSample = Date().addingTimeInterval(condition.withLock { _sampleInterval })
            }

            condition.lock()
            if !needsList && !stopped {
                condition.wait(until: min(nextSample, Date().addingTimeInterval(Self.idleTimeout)))
            }
            condition.unlock()
        }
    }

    /// Must be called with the condition locked.
    private func stop() {
        stopped = true
        if eventSocket >= 0 { shutdown(eventSocket, SHUT_RDWR) }
    }

    private func refreshList() {
        let listed = DockerEngine.containers(runtime)
        condition.withLock {
            (state.containers, listFailingSince) = Self.containers(after: listed, previous: state.containers,
                                                                   failingSince: listFailingSince, now: Date())
            if listed != nil { state.listedAt = Date() }
            if listed == nil { needsList = true }
            let live = Set(state.containers.map(\.id))
            state.samples = state.samples.filter { live.contains($0.key) }
            state.startedAt = state.startedAt.filter { live.contains($0.key) }
            previousCPU = previousCPU.filter { live.contains($0.key) }
        }
    }

    /// Stats and missing start times for every container, in parallel. A
    /// failed request keeps the previous sample instead of recording 0.
    private func sample() {
        let (containers, knownStarts) = condition.withLock { (state.containers, state.startedAt) }
        guard !containers.isEmpty else { return }
        var usages = [ContainerUsage?](repeating: nil, count: containers.count)
        var starts = [Date?](repeating: nil, count: containers.count)
        let results = NSLock()
        DispatchQueue.concurrentPerform(iterations: containers.count) { index in
            let container = containers[index]
            let usage = DockerEngine.usage(container.id, runtime: runtime)
            let started = knownStarts[container.id] == nil ? DockerEngine.startedAt(container.id, runtime: runtime) : nil
            results.withLock {
                usages[index] = usage
                starts[index] = started
            }
        }
        let now = Date()
        condition.withLock {
            for (index, container) in containers.enumerated() {
                if let started = starts[index] { state.startedAt[container.id] = started }
                guard let usage = usages[index] else { continue }
                var cpu = state.samples[container.id]?.cpu ?? 0
                if let previous = previousCPU[container.id] {
                    if usage.cpuNanoseconds >= previous.nanoseconds {
                        let elapsed = now.timeIntervalSince(previous.at)
                        if elapsed > 0 { cpu = Double(usage.cpuNanoseconds - previous.nanoseconds) / (elapsed * 1_000_000_000) * 100 }
                    } else {
                        // The counter only goes back when the container restarted.
                        state.startedAt[container.id] = nil
                        cpu = 0
                    }
                } else {
                    cpu = 0
                }
                previousCPU[container.id] = (usage.cpuNanoseconds, now)
                state.samples[container.id] = ContainerSample(memory: usage.memory, cpu: cpu, at: now)
            }
        }
    }

    // MARK: - Events

    /// Docker's event stream says when containers start, stop or restart, so
    /// the list is refetched only when it changes instead of on every scan.
    private func watchEvents() {
        while !isStopped {
            let socket = DockerEngine.openStream("/events?filters=%7B%22type%22%3A%5B%22container%22%5D%7D", runtime: runtime)
            guard socket >= 0 else {
                Thread.sleep(forTimeInterval: 2)
                continue
            }
            let alreadyStopped = condition.withLock {
                eventSocket = socket
                // Anything that happened while disconnected is picked up here.
                needsList = true
                condition.signal()
                return stopped
            }
            if !alreadyStopped { readEvents(socket) }
            condition.withLock { eventSocket = -1 }
            close(socket)
            if !isStopped { Thread.sleep(forTimeInterval: 1) }
        }
    }

    private func readEvents(_ socket: Int32) {
        var pending = Data()
        var headerDone = false
        var buffer = [UInt8](repeating: 0, count: 8 * 1024)
        while true {
            let count = recv(socket, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            pending.append(buffer, count: count)
            if !headerDone {
                guard let end = pending.range(of: Data("\r\n\r\n".utf8)) else { continue }
                pending.removeSubrange(..<end.upperBound)
                headerDone = true
            }
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(...newline)
                handle(event: Data(line))
            }
        }
    }

    private func handle(event line: Data) {
        guard let event = DockerEngine.parseEvent(line) else { return }
        condition.withLock {
            if event.action == "start" { state.startedAt[event.id] = event.time }
            if DockerEngine.listChangingActions.contains(event.action) {
                needsList = true
                condition.signal()
            }
        }
    }
}
