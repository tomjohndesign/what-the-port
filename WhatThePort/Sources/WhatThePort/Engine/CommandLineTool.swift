import Foundation

/// The `wtp` command: a symlink in /usr/local/bin to this app's executable,
/// which runs the terminal UI when invoked by that name. Linking the app's
/// path rather than a copy keeps it current through updates.
enum CommandLineTool {
    static let linkPath = "/usr/local/bin/wtp"

    enum State: Equatable {
        /// Not running from a stable app bundle, e.g. `swift run` or a translocated download.
        case unavailable
        case notInstalled
        case installed
        /// Something else is at the link path: another copy, a missing app or a different tool.
        case other(String)
    }

    /// Only an app bundle at a stable location can be linked to.
    static var executablePath: String? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              !path.contains("/AppTranslocation/") else { return nil }
        return path
    }

    static var state: State {
        guard let target = executablePath else { return .unavailable }
        let fileManager = FileManager.default
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkPath) else {
            return fileManager.fileExists(atPath: linkPath) ? .other(linkPath) : .notInstalled
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: "/usr/local/bin"))
            .resolvingSymlinksInPath().path
        return resolved == target ? .installed : .other(resolved)
    }

    /// Links the command, asking for an administrator password only when
    /// /usr/local/bin isn't writable. Returns an error message, or nil on
    /// success or when the password prompt is cancelled.
    static func install() -> String? {
        guard let target = executablePath else { return "Move WhatThePort to Applications first." }
        let fileManager = FileManager.default
        let directory = (linkPath as NSString).deletingLastPathComponent
        if fileManager.isWritableFile(atPath: directory) {
            do {
                if (try? fileManager.destinationOfSymbolicLink(atPath: linkPath)) != nil || fileManager.fileExists(atPath: linkPath) {
                    try fileManager.removeItem(atPath: linkPath)
                }
                try fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        return runAsAdministrator("mkdir -p \(shellQuote(directory)) && ln -sfn \(shellQuote(target)) \(shellQuote(linkPath))")
    }

    /// Removes the link, but only if it's ours.
    static func uninstall() -> String? {
        guard state == .installed else { return nil }
        let directory = (linkPath as NSString).deletingLastPathComponent
        if FileManager.default.isWritableFile(atPath: directory) {
            do {
                try FileManager.default.removeItem(atPath: linkPath)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        return runAsAdministrator("rm -f \(shellQuote(linkPath))")
    }

    private static func runAsAdministrator(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return nil }
        // -128: the password prompt was cancelled.
        if error[NSAppleScript.errorNumber] as? Int == -128 { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "The command couldn’t be installed."
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
