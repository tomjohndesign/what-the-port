import Foundation

/// A TCP port in LISTEN state and the process holding it.
struct ListeningSocket {
    let port: Int
    let pid: pid_t
    let command: String
    var addresses: [String]
}

struct SocketScan {
    var listening: [ListeningSocket] = []
    /// Inbound established connections, keyed by local port.
    var inboundConnections: [Int: Int] = [:]
}

/// Reads TCP sockets via `lsof`'s machine-readable output.
enum SocketScanner {
    static func scan() -> SocketScan {
        let output = runLsof()
        var result = SocketScan()
        var byPort: [Int: ListeningSocket] = [:]

        var pid: pid_t = 0
        var command = ""
        var state = ""
        var name = ""

        func flush() {
            guard !name.isEmpty else { return }
            if state == "LISTEN" {
                if let port = localPort(of: name) {
                    let address = String(name[..<(name.lastIndex(of: ":") ?? name.endIndex)])
                    if var existing = byPort[port] {
                        if existing.pid == pid, !existing.addresses.contains(address) {
                            existing.addresses.append(address)
                            byPort[port] = existing
                        }
                    } else {
                        byPort[port] = ListeningSocket(port: port, pid: pid, command: command, addresses: [address])
                    }
                }
            } else if state == "ESTABLISHED", let arrow = name.range(of: "->") {
                if let port = localPort(of: String(name[..<arrow.lowerBound])) {
                    result.inboundConnections[port, default: 0] += 1
                }
            }
            name = ""
            state = ""
        }

        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = pid_t(value) ?? 0
            case "c":
                command = value
            case "f":
                flush()
            case "n":
                name = value
            case "T":
                if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default:
                break
            }
        }
        flush()

        result.listening = byPort.values.sorted { $0.port < $1.port }
        return result
    }

    private static func localPort(of address: String) -> Int? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        return Int(address[address.index(after: colon)...])
    }

    private static func runLsof() -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN,ESTABLISHED", "-F", "pcnT"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
