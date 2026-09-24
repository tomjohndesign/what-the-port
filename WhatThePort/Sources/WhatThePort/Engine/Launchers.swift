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
    /// Opens a new terminal window that resumes the session, in the terminal
    /// chosen in Settings.
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
            TerminalLauncher.run(script: url, in: directory)
        } catch {
            NSSound.beep()
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Runs a script in a new window of the user's terminal of choice.
enum TerminalLauncher {
    struct Terminal {
        let id: String
        let name: String
        /// Arguments for terminals that take a command on launch; nil for ones
        /// that run a `.command` file they're asked to open.
        let arguments: ((_ script: String, _ directory: String) -> [String])?
    }

    static let terminals: [Terminal] = [
        Terminal(id: "com.apple.Terminal", name: "Terminal", arguments: nil),
        Terminal(id: "com.googlecode.iterm2", name: "iTerm", arguments: nil),
        // Ghostty asks for confirmation before running `-e` commands from another
        // app, but runs a script it's asked to open without prompting.
        Terminal(id: "com.mitchellh.ghostty", name: "Ghostty", arguments: nil),
        Terminal(id: "com.github.wez.wezterm", name: "WezTerm", arguments: { script, directory in ["start", "--cwd", directory, "--", "/bin/zsh", "-l", script] }),
        Terminal(id: "net.kovidgoyal.kitty", name: "kitty", arguments: { script, directory in ["--directory", directory, "/bin/zsh", "-l", script] }),
        Terminal(id: "io.alacritty", name: "Alacritty", arguments: { script, directory in ["--working-directory", directory, "-e", "/bin/zsh", "-l", script] }),
    ]

    static var installed: [Terminal] {
        terminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.id) != nil }
    }

    /// The chosen terminal if it's installed, otherwise Terminal.
    static var current: Terminal {
        let preferred = UserDefaults.standard.string(forKey: Preferences.terminal) ?? "com.apple.Terminal"
        return installed.first { $0.id == preferred } ?? terminals[0]
    }

    static func run(script: URL, in directory: String) {
        let terminal = current
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.id) else {
            NSWorkspace.shared.open(script)
            return
        }
        if let arguments = terminal.arguments {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments(script.path, directory)
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else {
            NSWorkspace.shared.open([script], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
