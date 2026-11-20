import Foundation

struct ProjectInfo: Equatable {
    var name: String
    var root: String?
    var framework: String?
    var branch: String?
    var isWorktree: Bool = false
    var worktreeName: String?
    var hasVercel: Bool = false
    var showsBranchPrefix: Bool = false

    /// The branch as lists show it: `tom/route-selection` is `route-selection`, unless prefixes are on.
    var listBranch: String? { showsBranchPrefix ? branch : branch?.components(separatedBy: "/").last }
    /// What lists call the server. The detail view and `wtp list` keep the full branch.
    var displayName: String { listBranch ?? name }
}

/// Works out what a server is for from its working directory: the project
/// manifest, framework, git branch and whether it lives in a worktree.
final class ProjectResolver {
    private struct Cached {
        let info: ProjectInfo
        let gitHeadPath: String?
        let resolvedAt: Date
    }

    private var cache: [String: Cached] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func resolve(cwd: String?, command: String?) -> ProjectInfo {
        guard let cwd else { return ProjectInfo(name: "Unknown") }

        // The command is part of the key: two servers in one folder can be
        // Vite and Storybook, or Vite and Bazel.
        let cacheKey = cwd + "\n" + (command ?? "")
        if let cached = cache[cacheKey], Date().timeIntervalSince(cached.resolvedAt) < 15 {
            var info = cached.info
            // Branches change often; HEAD is cheap to re-read every scan.
            if let head = cached.gitHeadPath { info.branch = Self.branch(fromHead: head) }
            return info
        }

        var info = ProjectInfo(name: URL(fileURLWithPath: cwd).lastPathComponent)
        var gitHeadPath: String?
        var foundManifest = false
        var ecosystem: Ecosystem?
        var directory = URL(fileURLWithPath: cwd)

        while directory.path != "/" && directory.path != home {
            let path = directory.path
            if !foundManifest, let manifest = Self.readManifest(in: path, command: command) {
                info.name = manifest.name ?? directory.lastPathComponent
                info.framework = manifest.framework
                ecosystem = manifest.ecosystem
                info.root = path
                info.hasVercel = FileManager.default.fileExists(atPath: path + "/.vercel/project.json")
                foundManifest = true
            }
            if gitHeadPath == nil, let git = Self.gitHead(in: path) {
                gitHeadPath = git.headPath
                info.isWorktree = git.isWorktree
                if git.isWorktree { info.worktreeName = directory.lastPathComponent }
                if info.root == nil { info.root = path }
            }
            if foundManifest && gitHeadPath != nil { break }
            directory.deleteLastPathComponent()
        }

        // A running command that names its tool beats a guess from the folder's
        // manifest: Bazel's server in a repo whose package.json lists Vite is Bazel.
        if let tool = Self.commandTool(command), tool.ecosystem == nil || tool.ecosystem != ecosystem {
            info.framework = tool.label
        }

        if let gitHeadPath { info.branch = Self.branch(fromHead: gitHeadPath) }
        cache[cacheKey] = Cached(info: info, gitHeadPath: gitHeadPath, resolvedAt: Date())
        return info
    }

    // MARK: - Manifests

    private enum Ecosystem { case javaScript, python, rust, go, ruby }

    private struct Manifest {
        var name: String?
        var framework: String?
        var ecosystem: Ecosystem
    }

    private static func readManifest(in directory: String, command: String?) -> Manifest? {
        let fm = FileManager.default
        let packageJSON = directory + "/package.json"
        if fm.fileExists(atPath: packageJSON),
           let data = fm.contents(atPath: packageJSON),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var deps: [String: String] = [:]
            for key in ["dependencies", "devDependencies"] {
                (json[key] as? [String: String])?.forEach { deps[$0.key] = $0.value }
            }
            return Manifest(name: json["name"] as? String, framework: jsFramework(deps: deps, command: command), ecosystem: .javaScript)
        }
        if let text = try? String(contentsOfFile: directory + "/pyproject.toml", encoding: .utf8) {
            return Manifest(name: tomlName(text, section: "project") ?? tomlName(text, section: "tool.poetry"),
                            framework: pythonFramework(command: command, manifest: text), ecosystem: .python)
        }
        if let text = try? String(contentsOfFile: directory + "/Cargo.toml", encoding: .utf8) {
            return Manifest(name: tomlName(text, section: "package"), framework: "Rust", ecosystem: .rust)
        }
        if let text = try? String(contentsOfFile: directory + "/go.mod", encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("module ") }) {
            let module = line.dropFirst("module ".count).trimmingCharacters(in: .whitespaces)
            return Manifest(name: module.split(separator: "/").last.map(String.init), framework: "Go", ecosystem: .go)
        }
        if fm.fileExists(atPath: directory + "/Gemfile") {
            let isRails = fm.fileExists(atPath: directory + "/config/application.rb")
            return Manifest(name: nil, framework: isRails ? "Rails" : "Ruby", ecosystem: .ruby)
        }
        return nil
    }

    /// The tool a server's command names, like `java`, `bazel(my-repo)` or
    /// `python3 manage.py runserver`. Runtimes that have a manifest carry its
    /// ecosystem, so that manifest's own detection still wins, e.g. Django from
    /// pyproject.toml. JavaScript runtimes return nil: `node server.js` gives
    /// no better answer than package.json.
    private static func commandTool(_ command: String?) -> (label: String, ecosystem: Ecosystem?)? {
        guard let command, let word = command.split(separator: " ").first else { return nil }
        // Bazel's server renames itself `bazel(<workspace>)`.
        let executable = word.prefix { $0 != "(" }.lowercased()
        let tools: [String: (String, Ecosystem?)] = [
            "bazel": ("Bazel", nil), "java": ("Java", nil),
            "gradle": ("Gradle", nil), "gradlew": ("Gradle", nil), "mvn": ("Maven", nil), "mvnw": ("Maven", nil),
            "php": ("PHP", nil), "php-fpm": ("PHP", nil), "dotnet": (".NET", nil),
            "beam.smp": ("Elixir", nil), "elixir": ("Elixir", nil), "mix": ("Elixir", nil),
            "go": ("Go", .go), "air": ("Go", .go), "cargo": ("Rust", .rust),
            "ruby": ("Ruby", .ruby), "rails": ("Rails", .ruby), "puma": ("Ruby", .ruby), "unicorn": ("Ruby", .ruby),
        ]
        if let (label, ecosystem) = tools[executable] { return (label, ecosystem) }
        if ["python", "python3", "uv", "poetry", "pipenv", "uvicorn", "gunicorn", "flask"].contains(executable) || executable.hasPrefix("python3.") {
            return (pythonFramework(command: command, manifest: "") ?? "Python", .python)
        }
        return nil
    }

    private static func jsFramework(deps: [String: String], command: String?) -> String? {
        let command = command?.lowercased() ?? ""
        if command.contains("storybook") {
            let version = deps["storybook"] ?? deps.first { $0.key.hasPrefix("@storybook/") }?.value
            return version.map { label("Storybook", version: $0) } ?? "Storybook"
        }
        let candidates: [(match: String, label: String)] = [
            ("next", "Next.js"),
            ("nuxt", "Nuxt"),
            ("@remix-run/dev", "Remix"),
            ("astro", "Astro"),
            ("@sveltejs/kit", "SvelteKit"),
            ("expo", "Expo"),
            ("@angular/core", "Angular"),
            ("vite", "Vite"),
            ("react-scripts", "Create React App"),
            ("hono", "Hono"),
            ("express", "Express"),
        ]
        for candidate in candidates {
            if let version = deps[candidate.match] { return label(candidate.label, version: version) }
        }
        return nil
    }

    private static func label(_ name: String, version: String) -> String {
        let major = version.drop { !$0.isNumber }.prefix { $0.isNumber }
        return major.isEmpty ? name : "\(name) \(major)"
    }

    private static func pythonFramework(command: String?, manifest: String) -> String? {
        let haystack = (command ?? "").lowercased() + manifest.lowercased()
        for (match, label) in [("django", "Django"), ("fastapi", "FastAPI"), ("flask", "Flask"), ("uvicorn", "Uvicorn"), ("gunicorn", "Gunicorn")] where haystack.contains(match) {
            return label
        }
        return "Python"
    }

    private static func tomlName(_ text: String, section: String) -> String? {
        var inSection = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line == "[\(section)]"
                continue
            }
            if inSection, line.hasPrefix("name"), let quote = line.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                let rest = line[line.index(after: quote)...]
                if let end = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) { return String(rest[..<end]) }
            }
        }
        return nil
    }

    // MARK: - Git

    private static func gitHead(in directory: String) -> (headPath: String, isWorktree: Bool)? {
        let gitPath = directory + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return (gitPath + "/HEAD", false) }

        // Worktrees and submodules have a `.git` file pointing at the real git dir.
        guard let contents = try? String(contentsOfFile: gitPath, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        var gitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitDir.hasPrefix("/") { gitDir = directory + "/" + gitDir }
        return (gitDir + "/HEAD", gitDir.contains("/worktrees/"))
    }

    private static func branch(fromHead headPath: String) -> String? {
        guard let head = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
    }
}
