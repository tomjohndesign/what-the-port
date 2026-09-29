import Foundation

/// Resource totals count a process once even when it listens on several ports.
/// Bar segments divide shared processes evenly between their visible rows.
struct ServerResources {
    private struct Identity: Hashable {
        let pid: pid_t
        let startedAt: Date
    }

    let memory: UInt64
    let cpu: Double
    let memoryByPort: [Int: Double]

    init(_ servers: [Server]) {
        var processes: [Identity: ServerProcess] = [:]
        var ports: [Identity: Set<Int>] = [:]
        for server in servers {
            for process in server.processes {
                let identity = Identity(pid: process.pid, startedAt: server.processStarts[process.pid] ?? .distantPast)
                processes[identity] = process
                ports[identity, default: []].insert(server.port)
            }
        }
        memory = processes.values.reduce(0) { $0 + $1.memory }
        cpu = processes.values.reduce(0) { $0 + $1.cpu }
        var shares: [Int: Double] = [:]
        for (identity, process) in processes {
            let owners = ports[identity] ?? []
            for port in owners {
                shares[port, default: 0] += Double(process.memory) / Double(owners.count)
            }
        }
        memoryByPort = shares
    }
}
