import ServiceManagement
import SwiftUI
import UserNotifications

/// A dot matrix whose dots animate individually between glyphs, staggered by
/// column, so any glyph can morph into any other.
struct DotMatrixView: View {
    let glyph: DotGlyph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 110

    var body: some View {
        let pitch = size / 5
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { column in
                        let dot = glyph.dot(row: row, column: column)
                        Circle()
                            .fill(dot == "a" ? Theme.amber : Theme.text1)
                            .opacity(dot == "." ? 0.12 : 1)
                            .frame(width: pitch * 0.64, height: pitch * 0.64)
                            .frame(width: pitch, height: pitch)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.28).delay(Double(column) * 0.04), value: glyph)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome, leaks, tools, vercel, done
}

struct OnboardingView: View {
    @ObservedObject var monitor: ServerMonitor
    @StateObject var status = OnboardingStatus()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State var step: OnboardingStep = .welcome
    var close: () -> Void = {}

    @AppStorage(Preferences.onboarded) private var onboarded = false
    @AppStorage(Preferences.vercelPreviews) private var previews = false
    @AppStorage(Preferences.thresholdGB) private var thresholdGB = 2.0
    @AppStorage(Preferences.cleanUpIdleHours) private var idleHours = 4
    @State private var heroGlyph: DotGlyph = .colon

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                DotMatrixView(glyph: heroGlyph)
                    .frame(height: 120)
                VStack(spacing: 8) {
                    Text(title).font(Theme.displaySans).foregroundStyle(Theme.text1)
                    Text(message)
                        .font(Theme.body)
                        .foregroundStyle(OnboardingStyle.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                card
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 36, leading: 32, bottom: 20, trailing: 32))

            SectionDivider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                        Circle().fill(Theme.text1.opacity(item == step ? 1 : 0.2)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                HStack(spacing: 8) { actions }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        }
        .frame(width: 480, height: 620)
        .background(Theme.windowBackground)
        .onAppear { updateHero(animated: false); loadStep() }
        .onChange(of: step) { _, _ in updateHero(animated: !reduceMotion); loadStep() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == .leaks { Task { await status.refreshSetup(force: true) } }
        }
    }

    // MARK: - Copy

    private var title: String {
        switch step {
        case .welcome: return "WhatThePort"
        case .leaks: return "Stay ahead of leaks"
        case .tools: return "Your tools, at a glance."
        case .vercel: return "Vercel previews"
        case .done: return "You’re set"
        }
    }

    private var message: String {
        switch step {
        case .welcome: return "Every dev server on your Mac, in the menu bar. What it is, what branch it’s on, and what it’s costing you."
        case .leaks: return "WhatThePort warns you when a server starts eating memory. It never sends anything off your Mac."
        case .tools: return "WhatThePort reads local session files and process info to put your servers in context."
        case .vercel: return "See the preview deployment for whatever branch each server is running. Optional."
        case .done: return "The dots settle into the colon in your menu bar. Press ⌥⌘P any time to open it."
        }
    }

    // MARK: - Cards

    @ViewBuilder private var card: some View {
        switch step {
        case .welcome:
            OnboardingCard {
                OnboardingRow(title: monitor.servers.isEmpty ? "No servers running right now" : "Found \(monitor.servers.count) \(monitor.servers.count == 1 ? "server" : "servers") running") {
                    Text(monitor.servers.prefix(3).map { ":\($0.port)" }.joined(separator: " ") + (monitor.servers.count > 3 ? " …" : ""))
                        .font(Theme.mono).foregroundStyle(Theme.text2)
                }
            }
        case .leaks:
            VStack(spacing: 18) {
                OnboardingCard {
                    OnboardingSummary(title: status.setupSummary, detail: "\(status.readyCount) of 2 ready")
                    RowDivider()
                    OnboardingRow(title: "Notifications", caption: status.notifications == .action("Not allowed", button: "Settings…") ? "Allow in System Settings" : "Memory and leak alerts") {
                        OnboardingConfirmation(state: status.notifications, action: notificationAction)
                    }
                    RowDivider()
                    OnboardingRow(title: "Launch at login", caption: status.login == .action("Needs approval", button: "Settings…") ? "Approve in System Settings" : "Opens when you sign in") {
                        OnboardingConfirmation(state: status.login, action: loginAction)
                    }
                }
                if let error = status.notificationError ?? status.loginError {
                    Text(error).font(OnboardingStyle.label).foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button("You can change these in Settings.") { openWindow(id: "settings") }
                    .buttonStyle(.plain).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary)
            }
        case .tools:
            OnboardingCard {
                OnboardingSummary(
                    title: status.isScanning ? "Checking this Mac…" : "\(status.detectedCount) \(status.detectedCount == 1 ? "tool" : "tools") detected",
                    detail: status.isScanning ? "\(status.detectedCount) of 4 found" : "Scan complete"
                )
                ForEach(OnboardingTool.allCases, id: \.self) { tool in
                    RowDivider()
                    OnboardingRow(title: tool.name, icon: AnyView(toolIcon(tool))) {
                        OnboardingConfirmation(state: status.tools[tool] ?? .loading("Checking…"), monospaced: true)
                    }
                }
            }
        case .vercel:
            OnboardingCard {
                OnboardingRow(title: "Show preview buttons",
                              caption: GitHubLookup.isAvailable ? "Uses Vercel’s GitHub deployments through gh" : "Needs the GitHub CLI (gh)") {
                    Toggle("", isOn: $previews).labelsHidden().toggleStyle(.switch)
                }
                .disabled(!GitHubLookup.isAvailable)
            }
        case .done:
            OnboardingCard {
                OnboardingRow(title: "Alert when a server uses more than") {
                    HStack(spacing: 6) {
                        TextField("", value: $thresholdGB, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder).font(Theme.mono).multilineTextAlignment(.trailing).frame(width: 48)
                        Text("GB").font(Theme.mono).foregroundStyle(Theme.text3)
                    }
                }
                RowDivider()
                OnboardingRow(title: "Suggest cleaning up idle servers after") {
                    Picker("", selection: $idleHours) {
                        ForEach([1, 2, 4, 8, 24], id: \.self) { Text("\($0)h").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder private func toolIcon(_ tool: OnboardingTool) -> some View {
        switch tool {
        case .claude: ToolIcon(agent: .claudeCode)
        case .codex: ToolIcon(agent: .codex)
        case .conductor: ToolIcon(systemName: "square.grid.2x2")
        case .github: ToolIcon(systemName: "arrow.triangle.branch")
        }
    }

    private func loadStep() {
        // Keep in-flight work when moving between steps; returning shows cached
        // results instead of replaying a scan. Reads never change preferences.
        switch step {
        case .leaks: Task { await status.refreshSetup() }
        case .tools: Task { await status.scanTools() }
        default: break
        }
    }

    private func notificationAction() {
        if case .action(_, "Settings…") = status.notifications {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        } else {
            Task { await status.allowNotifications() }
        }
    }

    private func loginAction() {
        if case .action(_, "Settings…") = status.login {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            Task { await status.addLoginItem() }
        }
    }

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        switch step {
        case .welcome:
            Button("Get started") { go(.leaks) }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        case .vercel:
            Button("Back") { go(.tools) }.buttonStyle(PillButtonStyle())
            Button("Skip") { previews = false; go(.done) }.buttonStyle(PillButtonStyle())
            Button("Continue") { go(.done) }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        case .done:
            Button("Open WhatThePort") { finish() }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        default:
            Button("Back") { go(OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome) }.buttonStyle(PillButtonStyle())
            Button("Continue") { go(OnboardingStep(rawValue: step.rawValue + 1) ?? .done) }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { step = next }
    }

    private func finish() {
        onboarded = true
        close()
        StatusItemOpener.open()
    }

    private func updateHero(animated: Bool) {
        switch step {
        case .welcome: heroGlyph = .colon
        case .leaks: heroGlyph = .leak
        case .tools: heroGlyph = .prompt
        case .vercel: heroGlyph = .triangle
        case .done:
            // The celebration: spark, burst, fade, then settle into the colon.
            let frames: [DotGlyph] = [
                DotGlyph(rows: [".....", ".....", "..#..", ".....", "....."]),
                DotGlyph(rows: [".....", "..#..", ".###.", "..#..", "....."]),
                .burst,
                DotGlyph(rows: ["#...#", ".....", ".....", ".....", "#...#"]),
                .colon,
            ]
            guard animated, !reduceMotion else { heroGlyph = .colon; return }
            for (index, frame) in frames.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(index)) { if step == .done { heroGlyph = frame } }
            }
        }
    }

}

// MARK: - Pieces

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
        .background(OnboardingStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(OnboardingStyle.divider, lineWidth: 1))
    }
}

private struct RowDivider: View {
    var body: some View { Rectangle().fill(OnboardingStyle.divider).frame(height: 1) }
}

private struct OnboardingRow<Control: View>: View {
    let title: String
    var caption: String?
    var icon: AnyView?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let icon { icon }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.text1)
                if let caption { Text(caption).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, caption == nil ? 10 : 14)
        .frame(minHeight: caption == nil ? 49 : 64)
        .accessibilityElement(children: .contain)
    }
}

private struct ToolIcon: View {
    var agent: AgentKind?
    var systemName: String?

    init(agent: AgentKind) { self.agent = agent }
    init(systemName: String) { self.systemName = systemName }

    var body: some View {
        Group {
            if let agent {
                AgentGlyph(kind: agent, size: 14, color: Theme.text1)
            } else if let systemName {
                Image(systemName: systemName).font(.system(size: 12)).foregroundStyle(Theme.text1)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
