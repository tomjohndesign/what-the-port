import AppKit
import SwiftUI

/// `WhatThePort --snapshot <dir>` scans for a few seconds, renders each popover
/// page with live data to PNG, and exits. Useful for checking the UI without
/// clicking the menu bar.
@MainActor
enum SnapshotRenderer {
    static func run(monitor: ServerMonitor, directory: String) {
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
            let view = PopoverRoot(monitor: monitor, route: route, startCleaning: cleaning)
                .background(Color(red: 0.125, green: 0.125, blue: 0.14))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)
                .background(Color(red: 0.043, green: 0.051, blue: 0.07))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: output.appendingPathComponent("\(name).png"))
            }
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
        exit(0)
    }

    /// AppKit-backed controls (toggles, pickers, forms) don't draw in
    /// ImageRenderer, so render them in a real off-screen window instead.
    static func renderWindow<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
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
