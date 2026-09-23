import AppKit

enum EditorLauncher {
    /// Editors offered in Settings, tried in this order when set to Automatic.
    static let editors: [(id: String, name: String)] = [
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("com.microsoft.VSCode", "Visual Studio Code"),
        ("dev.zed.Zed", "Zed"),
        ("com.sublimetext.4", "Sublime Text"),
    ]

    static var installedEditors: [(id: String, name: String)] {
        editors.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    static func open(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let preferred = UserDefaults.standard.string(forKey: Preferences.editor) ?? "auto"
        if preferred == "finder" {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return
        }
        let order = preferred == "auto" ? editors.map(\.id) : [preferred] + editors.map(\.id)
        for id in order {
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
