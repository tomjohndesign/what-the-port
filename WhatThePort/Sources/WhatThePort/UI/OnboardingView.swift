import ServiceManagement
import SwiftUI
import UserNotifications

/// A dot matrix whose dots animate individually between glyphs, staggered by
/// column, so any glyph can morph into any other.
struct DotMatrixView: View {
    let glyph: DotGlyph
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
                            .animation(.easeInOut(duration: 0.28).delay(Double(column) * 0.04), value: glyph)
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
    @State var step: OnboardingStep = .welcome
    var close: () -> Void = {}

    @AppStorage(Preferences.onboarded) private var onboarded = false
    @AppStorage(Preferences.linkClaude) private var linkClaude = true
    @AppStorage(Preferences.linkCodex) private var linkCodex = true
    @AppStorage(Preferences.linkConductor) private var linkConductor = true
    @AppStorage(Preferences.githubPullRequests) private var pullRequests = false
    @AppStorage(Preferences.vercelPreviews) private var previews = false
    @AppStorage(Preferences.thresholdGB) private var thresholdGB = 2.0
    @AppStorage(Preferences.cleanUpIdleHours) private var idleHours = 4
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
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
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                card
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 36, leading: 40, bottom: 20, trailing: 40))

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
        .onAppear { updateHero(animated: false); refreshNotificationStatus() }
        .onChange(of: step) { _, _ in updateHero(animated: true) }
    }

    // MARK: - Copy

    private var title: String {
        switch step {
        case .welcome: return "WhatThePort"
        case .leaks: return "Stay ahead of leaks"
        case .tools: return "Link your tools"
        case .vercel: return "Vercel previews"
        case .done: return "You’re set"
        }
    }

    private var message: String {
        switch step {
        case .welcome: return "Every dev server on your Mac, in the menu bar. What it is, what branch it’s on, and what it’s costing you."
        case .leaks: return "WhatThePort warns you when a server starts eating memory. It never sends anything off your Mac."
        case .tools: return "Found on this Mac. WhatThePort only reads local session files and process info."
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
            OnboardingCard {
                OnboardingRow(title: "Notifications", caption: "For memory and leak alerts") { notificationControl }
                RowDivider()
                OnboardingRow(title: "Launch at login") {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
        case .tools:
            OnboardingCard {
                toolRow(.claudeCode, name: "Claude Code", found: ToolDetection.claude ? "~/.claude" : "not found", caption: "Link servers to the session that started them", isOn: $linkClaude)
                RowDivider()
                toolRow(.codex, name: "Codex", found: ToolDetection.codex ? "~/.codex" : "not found", caption: "Link servers to Codex threads", isOn: $linkCodex)
                RowDivider()
                OnboardingRow(title: "Conductor", caption: "Show workspace names", icon: AnyView(ToolIcon(systemName: "square.grid.2x2")), detail: ToolDetection.conductor ? "installed" : "not found") {
                    Toggle("", isOn: $linkConductor).labelsHidden().toggleStyle(.switch)
                }
                RowDivider()
                OnboardingRow(title: "GitHub CLI", caption: "Show the pull request for each branch", icon: AnyView(ToolIcon(systemName: "arrow.triangle.branch")), detail: GitHubLookup.isAvailable ? "gh" : "not found") {
                    Toggle("", isOn: $pullRequests).labelsHidden().toggleStyle(.switch)
                }
                .disabled(!GitHubLookup.isAvailable)
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

    private func toolRow(_ kind: AgentKind, name: String, found: String, caption: String, isOn: Binding<Bool>) -> some View {
        OnboardingRow(title: name, caption: caption, icon: AnyView(ToolIcon(agent: kind)), detail: found) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    @ViewBuilder private var notificationControl: some View {
        switch notificationStatus {
        case .authorized, .provisional:
            Text("Allowed").font(Theme.body).foregroundStyle(Theme.text2)
        case .denied:
            Button("Open Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(PillButtonStyle())
        default:
            Button("Allow…") {
                Task {
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    refreshNotificationStatus()
                }
            }
            .buttonStyle(PillButtonStyle())
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
        withAnimation(.snappy(duration: 0.25)) { step = next }
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
            guard animated else { heroGlyph = .colon; return }
            for (index, frame) in frames.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(index)) { heroGlyph = frame }
            }
        }
    }

    private func refreshNotificationStatus() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
        }
    }
}

// MARK: - Pieces

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
    }
}

private struct RowDivider: View {
    var body: some View { SectionDivider().padding(.leading, 12) }
}

private struct OnboardingRow<Control: View>: View {
    let title: String
    var caption: String?
    var icon: AnyView?
    var detail: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let icon { icon }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(Theme.body).foregroundStyle(Theme.text1)
                    if let detail { Text(detail).font(Theme.monoCaption).foregroundStyle(Theme.text3) }
                }
                if let caption { Text(caption).font(Theme.caption).foregroundStyle(Theme.text3) }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
