import Foundation
import Testing
@testable import WhatThePort

struct AgentSessionResolverTests {
    private let id = "c0a8012e-0000-4000-8000-000000000043"

    @Test func copilotMetadataIsOptionalAndBounded() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let resolver = AgentSessionResolver(home: home)
        let environment = ["COPILOT_AGENT_SESSION_ID": id]

        let missing = try #require(resolver.resolve(environment: environment, cwd: "/shared/project"))
        #expect(missing.kind == .copilot)
        #expect(missing.id == id)
        #expect(missing.title == nil)
        #expect(missing.directory == nil)
        #expect(missing.metadataState == .unavailable)

        let workspace = home.appendingPathComponent(".copilot/session-state/\(id)/workspace.yaml")
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "cwd: /fixture/project\n".write(to: workspace, atomically: true, encoding: .utf8)
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.directory == "/fixture/project")
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.metadataState == .available)

        let prefix = "cwd: /fixture/project\n"
        let atLimit = prefix + String(repeating: " ", count: 64 * 1024 - prefix.utf8.count)
        try atLimit.write(to: workspace, atomically: true, encoding: .utf8)
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.directory == "/fixture/project")
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.metadataState == .available)

        try (atLimit + " ").write(to: workspace, atomically: true, encoding: .utf8)
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.directory == nil)
        #expect(resolver.resolve(environment: environment, cwd: "/shared/project")?.metadataState == .limited)
    }

    @Test func copilotDoesNotResolveFromMalformedIdentityOrCwd() {
        let resolver = AgentSessionResolver(home: FileManager.default.temporaryDirectory)
        #expect(resolver.resolve(environment: ["COPILOT_AGENT_SESSION_ID": "copilot-43"], cwd: "/shared/project") == nil)
        #expect(resolver.resolve(environment: [:], cwd: "/shared/project", codex: false) == nil)
    }

    @Test func unreadableCopilotWorkspaceKeepsMinimalAssociation() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent(".copilot/session-state/\(id)/workspace.yaml")
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "cwd: /fixture/project\n".write(to: workspace, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: workspace.path)

        let session = try #require(AgentSessionResolver(home: home).resolve(
            environment: ["COPILOT_AGENT_SESSION_ID": id], cwd: "/shared/project"
        ))
        #expect(session.id == id)
        #expect(session.directory == nil)
        #expect(session.title == nil)
        #expect(session.metadataState == .unavailable)
    }

    @Test func ambiguousCopilotSignalDoesNotFallBackToCodex() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("project")
        let sessions = home.appendingPathComponent(".codex/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try """
        {"payload":{"id":"codex-session","cwd":"\(project.path)"}}
        """.write(to: sessions.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let resolver = AgentSessionResolver(home: home)
        #expect(resolver.resolve(environment: [:], cwd: project.path)?.kind == .codex)
        #expect(resolver.resolve(
            environment: ["WTP_COPILOT_SESSION_AMBIGUOUS": "1"],
            cwd: project.path
        ) == nil)
    }

    @Test func malformedCopilotWorkspaceStaysLimitedWithoutCrashing() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent(".copilot/session-state/\(id)/workspace.yaml")
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "cwd:\n".write(to: workspace, atomically: true, encoding: .utf8)

        let session = try #require(AgentSessionResolver(home: home).resolve(
            environment: ["COPILOT_AGENT_SESSION_ID": id],
            cwd: "/shared/project"
        ))
        #expect(session.directory == nil)
        #expect(session.metadataState == .limited)
    }

    @Test func copilotWorkspaceValidatesIdentityFieldsAfterDirectory() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent(".copilot/session-state/\(id)/workspace.yaml")
        try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        cwd: /fixture/project
        sessionId: 11111111-1111-4111-8111-111111111111
        """.write(to: workspace, atomically: true, encoding: .utf8)

        let session = try #require(AgentSessionResolver(home: home).resolve(
            environment: ["COPILOT_AGENT_SESSION_ID": id],
            cwd: "/shared/project"
        ))
        #expect(session.directory == nil)
        #expect(session.metadataState == .limited)
    }
}
