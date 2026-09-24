import AppKit

/// Memory used by one app, with its helper processes folded in
/// (e.g. every "Google Chrome Helper" counts toward Google Chrome).
struct AppMemory: Identifiable, Equatable {
    let id: String
    let name: String
    let bundlePath: String?
    /// Set for coding agents, which have no app bundle of their own.
    let agent: AgentKind?
    let memory: UInt64
}

/// Adds up memory by app for everything that isn't a dev server. Only the
/// current user's processes are readable, so system daemons end up in the
/// "everything else" remainder. Use from one serial queue.
final class AppUsageScanner: @unchecked Sendable {
    private var bundleNames: [String: String] = [:]

    func scan(excluding excluded: Set<pid_t>) -> [AppMemory] {
        let processes = ProcessInspector.allProcesses()
        var paths: [pid_t: String?] = [:]
        func path(_ pid: pid_t) -> String? {
            if let cached = paths[pid] { return cached }
            let value = ProcessInspector.executablePath(pid)
            paths[pid] = value
            return value
        }

        var totals: [String: (name: String, bundle: String?, agent: AgentKind?, memory: UInt64)] = [:]
        for process in processes.values where !excluded.contains(process.pid) {
            guard let usage = ProcessInspector.usage(process.pid), usage.footprint > 0 else { continue }
            let owner = owner(of: process, processes: processes, path: path)
            totals[owner.key, default: (owner.name, owner.bundle, owner.agent, 0)].memory += usage.footprint
        }
        return totals
            .map { AppMemory(id: $0.key, name: $0.value.name, bundlePath: $0.value.bundle, agent: $0.value.agent, memory: $0.value.memory) }
            .sorted { $0.memory > $1.memory }
    }

    /// Who a process's memory belongs to: its own app bundle, a coding agent,
    /// the nearest app that launched it, or failing that its process name.
    private func owner(of process: ProcSnapshot, processes: [pid_t: ProcSnapshot],
                       path: (pid_t) -> String?) -> (key: String, name: String, bundle: String?, agent: AgentKind?) {
        // XPC helpers (WebKit content, app services) are children of launchd;
        // macOS records the app they work for as their "responsible" process.
        if let own = path(process.pid), let agent = Self.agent(forExecutable: own, comm: process.comm) {
            return ("agent:" + agent.rawValue, agent.rawValue, nil, agent)
        }
        if let responsible = Self.responsiblePid(process.pid), responsible != process.pid,
           let executable = path(responsible), let bundle = Self.appBundle(containing: executable) {
            return (bundle, displayName(forBundle: bundle), bundle, nil)
        }
        var current: ProcSnapshot? = process
        var hops = 0
        while let candidate = current, hops < 12 {
            if let executable = path(candidate.pid) {
                if let agent = Self.agent(forExecutable: executable, comm: candidate.comm) {
                    return ("agent:" + agent.rawValue, agent.rawValue, nil, agent)
                }
                if let bundle = Self.appBundle(containing: executable) {
                    return (bundle, displayName(forBundle: bundle), bundle, nil)
                }
            }
            guard candidate.ppid > 1 else { break }
            current = processes[candidate.ppid]
            hops += 1
        }
        return ("process:" + process.comm, process.comm, nil, nil)
    }

    /// `responsibility_get_pid_responsible_for_pid` is what Activity Monitor
    /// uses to group helpers under their app. It isn't in the public headers.
    private static let responsibleFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsiblePid(_ pid: pid_t) -> pid_t? {
        guard let function = responsibleFunction else { return nil }
        let result = function(pid)
        return result > 0 ? result : nil
    }

    /// The outermost real app bundle in a path, so nested helper apps roll up to
    /// their parent. Folders that merely end in ".app" (like Application
    /// Support/com.conductor.app) aren't bundles, so require an Info.plist.
    private static func appBundle(containing path: String) -> String? {
        var searchStart = path.startIndex
        while let range = path.range(of: ".app/", range: searchStart..<path.endIndex) {
            let candidate = String(path[..<range.lowerBound]) + ".app"
            if FileManager.default.fileExists(atPath: candidate + "/Contents/Info.plist") { return candidate }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func agent(forExecutable path: String, comm: String) -> AgentKind? {
        let lowered = path.lowercased()
        // Desktop apps like Claude.app are apps, not the CLI agents.
        if appBundle(containing: path) != nil, !lowered.contains("claude-code") { return nil }
        if comm == "claude" || lowered.contains("@anthropic-ai/claude-code") || lowered.hasSuffix("/claude") { return .claudeCode }
        if comm == "codex" || lowered.contains("/codex/") || lowered.hasSuffix("/codex") { return .codex }
        return nil
    }

    private func displayName(forBundle path: String) -> String {
        if let cached = bundleNames[path] { return cached }
        let info = Bundle(path: path)?.infoDictionary
        let name = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        bundleNames[path] = name
        return name
    }
}

@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
