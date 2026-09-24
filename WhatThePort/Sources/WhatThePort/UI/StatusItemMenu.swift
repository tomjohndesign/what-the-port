import AppKit

/// Right-click (or Control-click) menu for the menu bar icon. MenuBarExtra has
/// no API for one, so watch for secondary clicks on its status bar button.
@MainActor
enum StatusItemMenu {
    private static var eventMonitor: Any?

    static func install(monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let secondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            guard secondary, let window = event.window, window.className.contains("NSStatusBarWindow"),
                  let button = StatusItemOpener.findButton(in: window.contentView) else { return event }
            show(from: button, monitor: monitor, openSettings: openSettings)
            return nil
        }
    }

    private static func show(from button: NSStatusBarButton, monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ActionItem("Open WhatThePort") { StatusItemOpener.open() })

        let browser = NSMenuItem(title: "Open in Browser", action: nil, keyEquivalent: "")
        let servers = NSMenu()
        for server in monitor.servers {
            servers.addItem(ActionItem("localhost:\(String(server.port))  \(server.project.branch ?? server.project.name)") {
                Usage.record(.openBrowser)
                NSWorkspace.shared.open(server.url)
            })
        }
        browser.submenu = servers
        browser.isEnabled = !monitor.servers.isEmpty
        menu.addItem(browser)

        menu.addItem(.separator())
        let settings = ActionItem("Settings…", action: openSettings)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let updates = ActionItem("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
        updates.isEnabled = AppUpdater.shared.canCheckForUpdates
        menu.addItem(updates)

        let feedback = NSMenuItem(title: "Send Feedback", action: nil, keyEquivalent: "")
        feedback.submenu = NSMenu()
        feedback.submenu?.addItem(ActionItem("Report a Bug…") { NSWorkspace.shared.open(FeedbackLink.issue(.bug)) })
        feedback.submenu?.addItem(ActionItem("Suggest a Feature…") { NSWorkspace.shared.open(FeedbackLink.issue(.feature)) })
        menu.addItem(feedback)

        menu.addItem(.separator())
        let quit = ActionItem("Quit WhatThePort") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        button.highlight(false)
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
