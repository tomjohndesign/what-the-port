import Foundation

/// Resource totals count a process once even when it listens on several ports.
/// Bar segments divide shared processes evenly between their visible rows.
struct ServerResources {
    /// Containers count once like processes do, keyed by container id.
    private enum Identity: Hashable {
        case process(pid: pid_t, startedAt: Date)
        case container(String)
    }

    let memory: UInt64
    let cpu: Double
    let memoryByPort: [Int: Double]

    init(_ servers: [Server]) {
        var usage: [Identity: (memory: UInt64, cpu: Double)] = [:]
        var ports: [Identity: Set<Int>] = [:]
        for server in servers {
            if let container = server.container {
                let identity = Identity.container(container.id)
                usage[identity] = (server.memory, server.cpu)
                ports[identity, default: []].insert(server.port)
                continue
            }
            for process in server.processes {
                let identity = Identity.process(pid: process.pid, startedAt: server.processStarts[process.pid] ?? .distantPast)
                usage[identity] = (process.memory, process.cpu)
                ports[identity, default: []].insert(server.port)
            }
        }
        memory = usage.values.reduce(0) { $0 + $1.memory }
        cpu = usage.values.reduce(0) { $0 + $1.cpu }
        var shares: [Int: Double] = [:]
        for (identity, value) in usage {
            let owners = ports[identity] ?? []
            for port in owners {
                shares[port, default: 0] += Double(value.memory) / Double(owners.count)
            }
        }
        memoryByPort = shares
    }
}
