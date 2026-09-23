import AppKit

enum EditorLauncher {
    /// Editors to try, in order, for "Open in editor".
    private static let bundleIDs = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
        "dev.zed.Zed",
        "com.sublimetext.4",
    ]

    static func open(_ path: String) {
        let url = URL(fileURLWithPath: path)
        for id in bundleIDs {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}

enum SessionLauncher {
    /// Opens a new Terminal window that resumes the session. Uses a `.command`
    /// file rather than AppleScript so no Automation permission is needed.
    static func resume(_ session: AgentSession, fallbackDirectory: String?) {
        let directory = session.directory ?? fallbackDirectory ?? NSHomeDirectory()
        let script = """
        #!/bin/zsh -l
        cd \(shellQuote(directory))
        \(session.kind.resumeCommand) \(shellQuote(session.id))
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whattheport-resume-\(session.shortID).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
