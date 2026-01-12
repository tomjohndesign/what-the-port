import Foundation
import UserNotifications

@MainActor
final class PortMonitor: ObservableObject {
    @Published var ports: [ListeningPort] = []
    @Published var allowlist: Set<String> = PortScanner.defaultAllowlist

    private let scanner = PortScanner()
    private var previousPorts: Set<Int> = []
    private var timer: Timer?

    var minPort: Int = 3000
    var maxPort: Int = 9999

    init() {
        loadAllowlist()
    }

    func start() {
        requestNotificationPermission()
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        let current = scanner.scan(minPort: minPort, maxPort: maxPort, allowlist: allowlist)
        let currentSet = Set(current.map(\.port))

        let added = currentSet.subtracting(previousPorts)
        let removed = previousPorts.subtracting(currentSet)

        for port in added {
            if let p = current.first(where: { $0.port == port }) {
                notify(title: "Port Started", body: "\(p.process) on port \(p.port)")
            }
        }

        for port in removed {
            notify(title: "Port Stopped", body: "Port \(port) is no longer listening")
        }

        previousPorts = currentSet
        ports = current
    }

    func stopProcess(_ port: ListeningPort) {
        _ = scanner.stopProcess(pid: port.pid)
        // Rescan after a brief delay to update the list
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.scan()
        }
    }

    func addToAllowlist(_ process: String) {
        allowlist.insert(process)
        saveAllowlist()
        scan()
    }

    func removeFromAllowlist(_ process: String) {
        allowlist.remove(process)
        saveAllowlist()
        scan()
    }

    func resetAllowlist() {
        allowlist = PortScanner.defaultAllowlist
        saveAllowlist()
        scan()
    }

    private func loadAllowlist() {
        if let saved = UserDefaults.standard.array(forKey: "allowlist") as? [String] {
            allowlist = Set(saved)
        }
    }

    private func saveAllowlist() {
        UserDefaults.standard.set(Array(allowlist), forKey: "allowlist")
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
