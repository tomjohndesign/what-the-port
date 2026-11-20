import Combine
import Testing
@testable import WhatThePort

@MainActor
struct MenuBarIconStateTests {
    /// Each redraw of the menu bar icon makes WindowServer log an error, so
    /// scans that don't change the icon mustn't publish (issue #58).
    @Test func testPublishesOnlyWhenTheIconChanges() {
        let state = MenuBarIconState()
        var changes = 0
        let subscription = state.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        state.update(count: 0, needsAttention: false)
        #expect(changes == 0)

        state.update(count: 3, needsAttention: false)
        state.update(count: 3, needsAttention: false)
        #expect(changes == 1)

        state.update(count: 3, needsAttention: true)
        state.update(count: 3, needsAttention: true)
        #expect(changes == 2)
        #expect(state.count == 3)
        #expect(state.needsAttention)
    }
}
