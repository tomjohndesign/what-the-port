import Foundation
import Testing
@testable import WhatThePort

struct ProjectResolverTests {
    @Test func bazelCommandOverridesManifestFrameworkWithoutPollutingTheCache() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"name":"example-project","devDependencies":{"vite":"7.0.0"}}"#.utf8)
            .write(to: directory.appendingPathComponent("package.json"))

        let resolver = ProjectResolver()
        #expect(resolver.resolve(cwd: directory.path, command: "vite --host localhost").framework == "Vite 7")
        for command in ["bazel(example-project) -jar A-server.jar", "bazel build //:app", "/opt/bin/bazelisk build //:app"] {
            let project = resolver.resolve(cwd: directory.path, command: command)
            #expect(project.name == "example-project")
            #expect(project.framework == "Bazel")
            #expect(resolver.resolve(cwd: directory.path, command: "vite --host localhost").framework == "Vite 7")
        }
        #expect(resolver.resolve(cwd: directory.path, command: "node bazel-helper.js").framework == "Vite 7")
        #expect(resolver.resolve(cwd: directory.path, command: "node /bazel(work)/server.js").framework == "Vite 7")
    }

    @Test func bazelIsRecognizedWithoutAProjectManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let project = ProjectResolver().resolve(cwd: directory.path, command: "bazel(example-project) -jar A-server.jar")
        #expect(project.framework == "Bazel")
    }
}
