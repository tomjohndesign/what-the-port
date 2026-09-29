import Testing
@testable import WhatThePort

struct PaneWorkspaceTests {
    @Test func linksToTheTerminalThatStartedTheServer() throws {
        let workspace = try #require(PaneWorkspace(environment: [
            "PANE_SESSION_ID": "694ece4b",
            "PANE_PANEL_ID": "b9b0c2b8",
            "PANE_WORKSPACE_PATH": "/Users/me/app/worktrees/pricing-page",
        ]))
        #expect(workspace.name == "pricing-page")
        #expect(workspace.link.absoluteString == "pane://open?pane=694ece4b&panel=b9b0c2b8")
    }

    @Test func ignoresProcessesOutsidePane() {
        #expect(PaneWorkspace(environment: ["PANE_WORKSPACE_PATH": "/Users/me/app"]) == nil)
    }
}
