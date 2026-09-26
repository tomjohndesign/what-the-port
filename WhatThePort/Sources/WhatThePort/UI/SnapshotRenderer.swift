import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

/// `WhatThePort --snapshot <dir>` scans for a few seconds, renders each popover
/// page with live data to PNG, and exits. Useful for checking the UI without
/// clicking the menu bar.
@MainActor
enum SnapshotRenderer {
    static func run(monitor: ServerMonitor, directory: String) {
        configureAppearance()
        let scheme: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        for _ in 0..<5 {
            monitor.scanNow()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        monitor.scanNow()

        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var pages: [(String, PopoverRoute, Bool)] = [("servers", .servers, false), ("cleanup", .servers, true)]
        if let first = monitor.servers.first(where: { $0.agent != nil }) ?? monitor.servers.first {
            pages.insert(("detail", .detail(port: first.port), false), at: 1)
        }
        for (name, route, cleaning) in pages {
            // Render the same page at the popover's width without its menu-bar
            // window fitter, which would resize away the snapshot padding.
            let view = snapshotPage(monitor: monitor, route: route, cleaning: cleaning)
                .frame(width: Theme.popoverWidth)
                .background(Theme.popoverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)
                .background(Theme.snapshotBackground)
                .environment(\.colorScheme, scheme)
            let size = NSHostingView(rootView: view).fittingSize
            renderWindow(view, size: size, to: output.appendingPathComponent("\(name).png"))
        }

        for pane in SettingsPane.allCases {
            renderWindow(SettingsView(monitor: monitor, initialPane: pane), size: CGSize(width: 740, height: 560),
                         to: output.appendingPathComponent("settings-\(pane.id.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")).png"))
        }

        for step in OnboardingStep.allCases {
            renderWindow(OnboardingView(monitor: monitor, step: step), size: CGSize(width: 480, height: 620),
                         to: output.appendingPathComponent("onboarding-\(step.rawValue + 1).png"))
        }

        // App icon master: 824pt artwork centred on a 1024pt canvas, per the macOS icon grid.
        let iconRenderer = ImageRenderer(content: AppIconView(size: 824).frame(width: 1024, height: 1024))
        iconRenderer.scale = 1
        if let cgImage = iconRenderer.cgImage,
           let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("appicon-1024.png"))
        }

        let icon = MenuBarIcon.image(glyph: monitor.needsAttention ? .alert : .colon, count: monitor.servers.count)
        if let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("menubar-icon.png"))
        }

        for server in monitor.servers {
            print(":\(server.port)  \(server.project.name)  branch=\(server.project.branch ?? "-")  root=\(server.command ?? "-")  procs=\(server.processes.count)  mem=\(Format.bytesString(server.memory))  cpu=\(Format.percent(server.cpu))  agent=\(server.agent.map { "\($0.kind.rawValue): \($0.title ?? "?")" } ?? "-")  ws=\(server.conductorWorkspace ?? "-")")
        }
        print("apps: " + monitor.otherApps.prefix(8).map { "\($0.name) \(Format.bytesString($0.memory))" }.joined(separator: ", "))
        exit(0)
    }

    @ViewBuilder private static func snapshotPage(monitor: ServerMonitor, route: PopoverRoute, cleaning: Bool) -> some View {
        switch route {
        case .servers:
            ServersView(monitor: monitor, startCleaning: cleaning, openServer: { _ in }, openSettings: {})
        case .detail(let port):
            if let server = monitor.server(port: port) {
                ServerDetailView(server: server, monitor: monitor, back: {})
            }
        }
    }

    /// Deterministic onboarding samples. These services never request real
    /// notification permission, alter login items, or change preferences.
    static func runOnboarding(monitor: ServerMonitor, directory: String) {
        configureAppearance()
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples: [(String, OnboardingStep, UNAuthorizationStatus, SMAppService.Status)] = [
            ("tools-loading", .tools, .authorized, .enabled),
            ("tools-confirmed", .tools, .authorized, .enabled),
            ("tools-missing", .tools, .authorized, .enabled),
            ("setup-actions", .leaks, .notDetermined, .notRegistered),
            ("setup-pending", .leaks, .notDetermined, .notRegistered),
            ("setup-confirmed", .leaks, .authorized, .enabled),
            ("setup-approval", .leaks, .denied, .requiresApproval),
        ]
        for (name, step, authorization, login) in samples {
            let services = OnboardingServices(
                detect: { tool in
                    if name == "tools-loading", tool != .claude { try? await Task.sleep(for: .seconds(5)) }
                    return name != "tools-missing" || tool != .github
                },
                notifications: { authorization },
                requestNotifications: { try await Task.sleep(for: .seconds(5)) },
                login: { login },
                registerLogin: { try await Task.sleep(for: .seconds(5)) }
            )
            let status = OnboardingStatus(services: services)
            if name == "setup-pending" {
                Task {
                    await status.refreshSetup()
                    async let notification: Void = status.allowNotifications()
                    async let registration: Void = status.addLoginItem()
                    _ = await (notification, registration)
                }
            }
            renderWindow(OnboardingView(monitor: monitor, status: status, step: step),
                         size: CGSize(width: 480, height: 620),
                         to: output.appendingPathComponent("\(name).png"))
        }
        // What people updating from before usage sharing see.
        renderWindow(OnboardingView(monitor: monitor, step: .usage, usageOnly: true), size: CGSize(width: 480, height: 620),
                     to: output.appendingPathComponent("usage-after-update.png"))
        exit(0)
    }

    private static func configureAppearance() {
        // Override only this snapshot process; never change the Mac's appearance.
        if let index = CommandLine.arguments.firstIndex(of: "--appearance"),
           let value = CommandLine.arguments.dropFirst(index + 1).first {
            guard value == "light" || value == "dark" else {
                fputs("--appearance must be light or dark\n", stderr)
                exit(1)
            }
            NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        }
    }

    /// AppKit-backed controls (toggles, pickers, forms) don't draw in
    /// ImageRenderer, so render them in a real off-screen window instead.
    static func renderWindow<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSApp.effectiveAppearance
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        // Capturing your own window doesn't need Screen Recording permission.
        // CGWindowListCreateImage is hidden from the Swift SDK, so look it up.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        guard let image = createImage(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFraming | bestResolution)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
