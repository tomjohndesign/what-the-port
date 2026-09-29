import Foundation

/// Ownership is determined using every listening socket, including ports and
/// processes hidden by the user's filters. A shared task runner is not a server.
struct ProcessTree {
    let processes: [pid_t: ProcSnapshot]
    let children: [pid_t: [pid_t]]
    let portsByPID: [pid_t: Set<Int>]
    let listenersByPort: [Int: Set<pid_t>]

    init(processes: [pid_t: ProcSnapshot], sockets: SocketScan) {
        self.processes = processes
        var children: [pid_t: [pid_t]] = [:]
        for process in processes.values { children[process.ppid, default: []].append(process.pid) }
        self.children = children
        var listeners = sockets.listenerPidsByPort
        for socket in sockets.listening { listeners[socket.port, default: []].insert(socket.pid) }
        listenersByPort = listeners
        var ports: [pid_t: Set<Int>] = [:]
        for (port, pids) in listeners {
            for pid in pids { ports[pid, default: []].insert(port) }
        }
        portsByPID = ports
    }

    /// Reloaders/workers sharing a socket belong to the same service, as do
    /// multiple ports opened by one PID. Follow shared sockets transitively.
    func service(containing pid: pid_t) -> Set<pid_t> {
        var result: Set<pid_t> = [pid]
        var pending = [pid]
        while let current = pending.popLast() {
            for port in portsByPID[current] ?? [] {
                for peer in listenersByPort[port] ?? [] where result.insert(peer).inserted {
                    pending.append(peer)
                }
            }
        }
        return result
    }

    func containsOtherService(below pid: pid_t, service: Set<pid_t>) -> Bool {
        var pending = [pid]
        var seen = Set<pid_t>()
        while let current = pending.popLast() {
            guard seen.insert(current).inserted else { continue }
            if portsByPID[current] != nil && !service.contains(current) { return true }
            pending.append(contentsOf: children[current] ?? [])
        }
        return false
    }

    func descendants(of root: pid_t, service: Set<pid_t>) -> [(ProcSnapshot, Int)] {
        var result: [(ProcSnapshot, Int)] = []
        var seen = Set<pid_t>()
        func visit(_ pid: pid_t, depth: Int) {
            guard seen.insert(pid).inserted, let process = processes[pid] else { return }
            result.append((process, depth))
            for child in (children[pid] ?? []).sorted() {
                // Also avoid non-listening supervisors of a different service.
                if !containsOtherService(below: child, service: service) { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return result
    }
}
