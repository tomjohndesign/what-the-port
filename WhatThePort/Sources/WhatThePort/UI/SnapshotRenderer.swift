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

        let icon = MenuBarIcon.image(glyph: monitor.needsAttention ? .alert : .colon, count: monitor.servers.count)
        if let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("menubar-icon.png"))
        }

        for server in monitor.servers {
            print(":\(server.port)  \(server.project.name)  branch=\(server.project.branch ?? "-")  root=\(server.command ?? "-")  procs=\(server.processes.count)  mem=\(Format.bytesString(server.memory))  cpu=\(Format.percent(server.cpu))  agent=\(server.agent.map { "\($0.kind.rawValue): \($0.title ?? "?")" } ?? "-")  ws=\(server.conductorWorkspace ?? "-")")
        }
        exit(0)
    }
}
