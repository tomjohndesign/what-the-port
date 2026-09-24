import ServiceManagement
import UserNotifications
import Testing
@testable import WhatThePort

@MainActor
struct OnboardingStatusTests {
    private func services() -> OnboardingServices {
        OnboardingServices(detect: { _ in true }, notifications: { .notDetermined },
                           requestNotifications: {}, login: { .notRegistered }, registerLogin: {})
    }

    @Test func testOnlyConfirmedSystemStatesShowSuccess() {
        for state in [UNAuthorizationStatus.authorized, .provisional] {
            #expect(OnboardingStatus.notificationState(state) == .success("Allowed"))
        }
        #expect(OnboardingStatus.notificationState(.denied) == .action("Not allowed", button: "Settings…"))
        #expect(OnboardingStatus.notificationState(.notDetermined) == .action("Not allowed", button: "Allow…"))
        #expect(OnboardingStatus.notificationState(nil) == .unavailable("Unavailable"))
        #expect(OnboardingStatus.loginState(.enabled) == .success("Added"))
        #expect(OnboardingStatus.loginState(.requiresApproval) == .action("Needs approval", button: "Settings…"))
        #expect(OnboardingStatus.loginState(.notFound) == .unavailable("Unavailable"))
    }

    @Test func testDiscoveryPublishesIndependentlyAndCachesResults() async {
        let gates = Dictionary(uniqueKeysWithValues: OnboardingTool.allCases.map { ($0, Gate<Bool>()) })
        var calls = 0
        var services = services()
        services.detect = { tool in calls += 1; return await gates[tool]!.wait() }
        let model = OnboardingStatus(services: services)
        let scan = Task { await model.scanTools() }
        await eventually { calls == 4 }
        gates[.codex]!.resolve(true)
        await eventually { model.tools[.codex] == .success("~/.codex") }
        #expect(model.isScanning)
        #expect(model.detectedCount == 1)
        #expect(model.tools[.github] == nil)
        gates[.github]!.resolve(false)
        gates[.claude]!.resolve(true)
        gates[.conductor]!.resolve(true)
        await scan.value
        #expect(!(model.isScanning))
        #expect(model.detectedCount == 3)
        #expect(model.tools[.github] == .unavailable("Not found"))
        await model.scanTools()
        #expect(calls == 4)
    }

    @Test func testDiscoveryAndRefreshNeverRequestPermissionOrRegisterLogin() async {
        var reads = 0
        var services = services()
        services.notifications = { reads += 1; return .authorized }
        services.login = { .enabled }
        services.requestNotifications = { Issue.record("Read-only refresh must not request permission") }
        services.registerLogin = { Issue.record("Read-only refresh must not register login") }
        let model = OnboardingStatus(services: services)
        await model.scanTools()
        await model.refreshSetup()
        await model.refreshSetup()
        #expect(reads == 1)
        #expect(model.readyCount == 2)
        await model.refreshSetup(force: true)
        #expect(reads == 2)
    }

    @Test func testNotificationWaitsForActualResultAndPreventsDuplicateRequests() async {
        let request = Gate<Void>()
        var authorization: UNAuthorizationStatus = .notDetermined
        var calls = 0
        var services = services()
        services.notifications = { authorization }
        services.requestNotifications = { calls += 1; await request.wait() }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        let operation = Task { await model.allowNotifications() }
        await eventually { calls == 1 }
        #expect(model.notifications == .loading("Waiting…"))
        await model.allowNotifications()
        await model.refreshSetup(force: true)
        #expect(calls == 1)
        #expect(model.notifications == .loading("Waiting…"))
        authorization = .denied
        request.resolve(())
        await operation.value
        #expect(model.notifications == .action("Not allowed", button: "Settings…"))
        #expect(model.readyCount == 0)
    }

    @Test func testLoginRequiresApprovalUntilSystemReportsEnabled() async {
        let registration = Gate<Void>()
        var login: SMAppService.Status = .notRegistered
        var calls = 0
        var services = services()
        services.login = { login }
        services.registerLogin = { calls += 1; await registration.wait() }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        let operation = Task { await model.addLoginItem() }
        await eventually { calls == 1 }
        #expect(model.login == .loading("Adding…"))
        await model.addLoginItem()
        #expect(calls == 1)
        login = .requiresApproval
        registration.resolve(())
        await operation.value
        #expect(!(model.login.isSuccess))
        #expect(model.login == .action("Needs approval", button: "Settings…"))
        login = .enabled
        await model.refreshSetup(force: true)
        #expect(model.login == .success("Added"))
    }

    @Test func testErrorsRemainActionableAndRetryClearsError() async {
        struct Failed: Error {}
        var fail = true
        var login: SMAppService.Status = .notRegistered
        var notifications: UNAuthorizationStatus = .notDetermined
        var services = services()
        services.notifications = { notifications }
        services.login = { login }
        services.requestNotifications = { if fail { throw Failed() }; notifications = .authorized }
        services.registerLogin = { if fail { throw Failed() }; login = .enabled }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        await model.allowNotifications()
        await model.addLoginItem()
        #expect(model.notificationError != nil)
        #expect(model.loginError != nil)
        #expect(model.readyCount == 0)
        fail = false
        await model.allowNotifications()
        await model.addLoginItem()
        #expect(model.notificationError == nil)
        #expect(model.loginError == nil)
        #expect(model.readyCount == 2)
    }

    @Test func testLateRefreshCannotOverwriteCompletedRequest() async {
        let stale = Gate<UNAuthorizationStatus?>()
        var reads = 0
        var services = services()
        services.notifications = {
            reads += 1
            if reads == 2 { return await stale.wait() }
            return reads > 2 ? .authorized : .notDetermined
        }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        let refresh = Task { await model.refreshSetup(force: true) }
        await eventually { reads == 2 }
        await model.allowNotifications()
        #expect(model.notifications == .success("Allowed"))
        stale.resolve(.notDetermined)
        await refresh.value
        #expect(model.notifications == .success("Allowed"))
    }

    @Test func testCancellationLeavesDiscoveryRetryable() async {
        let gate = Gate<Bool>()
        var services = services()
        services.detect = { _ in await gate.wait() }
        let model = OnboardingStatus(services: services)
        let scan = Task { await model.scanTools() }
        await eventually { gate.count == 4 }
        scan.cancel()
        gate.resolve(true)
        await scan.value
        #expect(model.isScanning)
        #expect(model.tools.isEmpty)
        await model.scanTools()
        #expect(!(model.isScanning))
        #expect(model.detectedCount == 4)
    }

    private func eventually(_ predicate: () -> Bool) async {
        for _ in 0..<1000 {
            if predicate() { return }
            await Task.yield()
        }
        Issue.record("Condition did not become true")
    }
}

@MainActor
private final class Gate<Value> {
    private var pending: [CheckedContinuation<Value, Never>] = []
    private var result: Value?
    var count: Int { pending.count }

    func wait() async -> Value {
        if let result { return result }
        return await withCheckedContinuation { pending.append($0) }
    }

    func resolve(_ value: Value) {
        result = value
        let waiting = pending
        pending.removeAll()
        waiting.forEach { $0.resume(returning: value) }
    }
}
