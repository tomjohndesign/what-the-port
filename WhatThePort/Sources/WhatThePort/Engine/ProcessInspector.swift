import Darwin
import Foundation

/// A lightweight snapshot of one process from the kernel's process table.
struct ProcSnapshot {
    let pid: pid_t
    let ppid: pid_t
    let comm: String
    let startTime: Date
}

/// Launch details for a process, read from `KERN_PROCARGS2`.
struct ProcArgs {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
}

/// Memory footprint and cumulative CPU time for a process.
struct ProcUsage {
    let footprint: UInt64
    let cpuNanoseconds: UInt64
}

/// Thin wrappers over libproc and sysctl. Everything here works for processes
/// owned by the current user without any special entitlements.
enum ProcessInspector {
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func allProcesses() -> [pid_t: ProcSnapshot] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [:] }

        var result: [pid_t: ProcSnapshot] = [:]
        result.reserveCapacity(Int(count))
        for pid in pids.prefix(Int(count)) where pid > 0 {
            if let snapshot = snapshot(pid) {
                result[pid] = snapshot
            }
        }
        return result
    }

    static func snapshot(_ pid: pid_t) -> ProcSnapshot? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let comm = string(fromTuple: info.pbi_comm)
        let start = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        return ProcSnapshot(pid: pid, ppid: pid_t(info.pbi_ppid), comm: comm, startTime: start)
    }

    static func usage(_ pid: pid_t) -> ProcUsage? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        let ticks = info.ri_user_time + info.ri_system_time
        let nanoseconds = ticks * timebase.numer / timebase.denom
        return ProcUsage(footprint: info.ri_phys_footprint, cpuNanoseconds: nanoseconds)
    }

    static func currentDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = string(fromTuple: info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    static func arguments(_ pid: pid_t) -> ProcArgs? {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argMax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &argMax, &size, nil, 0) == 0, argMax > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: Int(argMax))
        mib = [CTL_KERN, KERN_PROCARGS2, pid]
        size = Int(argMax)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size

        func readString() -> String? {
            guard index < size else { return nil }
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            let value = String(decoding: buffer[start..<index], as: UTF8.self)
            index += 1
            return value
        }

        guard let executable = readString() else { return nil }
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        for _ in 0..<max(argc, 0) {
            guard let arg = readString() else { break }
            args.append(arg)
        }

        var env: [String: String] = [:]
        while let entry = readString(), !entry.isEmpty {
            if let equals = entry.firstIndex(of: "=") {
                env[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
            }
        }
        return ProcArgs(executablePath: executable, arguments: args, environment: env)
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let chars = raw.bindMemory(to: CChar.self)
            guard let base = chars.baseAddress else { return "" }
            return String(cString: base)
        }
    }
}
