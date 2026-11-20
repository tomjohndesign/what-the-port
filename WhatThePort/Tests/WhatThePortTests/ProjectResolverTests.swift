import Foundation
import Testing
@testable import WhatThePort

struct ProjectResolverTests {
    private func project(_ files: [String: String]) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return directory.path
    }

    private let viteManifest = #"{"name":"example-project","devDependencies":{"vite":"7.0.0","storybook":"9.1.0"}}"#

    @Test func aCommandThatNamesItsToolBeatsTheManifestsGuess() throws {
        let cwd = try project(["package.json": viteManifest])
        let resolver = ProjectResolver()
        let bazel = resolver.resolve(cwd: cwd, command: "bazel(example-project) -jar A-server.jar")
        #expect(bazel.framework == "Bazel")
        #expect(bazel.name == "example-project", "The manifest still names the project")
        #expect(resolver.resolve(cwd: cwd, command: "java -jar app.jar").framework == "Java")
        #expect(resolver.resolve(cwd: cwd, command: "python3 -m http.server").framework == "Python")
        #expect(resolver.resolve(cwd: cwd, command: "go run .").framework == "Go")
    }

    @Test func javaScriptServersStillReadTheManifest() throws {
        let cwd = try project(["package.json": viteManifest])
        let resolver = ProjectResolver()
        #expect(resolver.resolve(cwd: cwd, command: "vite").framework == "Vite 7")
        #expect(resolver.resolve(cwd: cwd, command: "server.js --port 3000").framework == "Vite 7")
        #expect(resolver.resolve(cwd: cwd, command: nil).framework == "Vite 7")
    }

    @Test func serversSharingAFolderKeepTheirOwnLabels() throws {
        let cwd = try project(["package.json": viteManifest])
        let resolver = ProjectResolver()
        #expect(resolver.resolve(cwd: cwd, command: "vite").framework == "Vite 7")
        #expect(resolver.resolve(cwd: cwd, command: "storybook dev -p 6006").framework == "Storybook 9")
        #expect(resolver.resolve(cwd: cwd, command: "bazel(example-project)").framework == "Bazel")
        #expect(resolver.resolve(cwd: cwd, command: "vite").framework == "Vite 7")
    }

    @Test func aRuntimesOwnManifestStillWins() throws {
        let python = try project(["pyproject.toml": "[project]\nname = \"api\"\ndependencies = [\"fastapi\"]\n"])
        #expect(ProjectResolver().resolve(cwd: python, command: "python uvicorn main:app").framework == "FastAPI")
        let rails = try project(["Gemfile": "source 'https://rubygems.org'\n"])
        #expect(ProjectResolver().resolve(cwd: rails, command: "ruby bin/rails server").framework == "Ruby")
    }
}
