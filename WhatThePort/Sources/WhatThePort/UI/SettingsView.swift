import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case alerts = "Alerts"
    case cleanUp = "Clean up"
    case ports = "Ports & processes"
    case integrations = "Integrations"
    case about = "About"

    var id: String { rawValue }

    var glyph: DotGlyph {
        switch self {
        case .general: return .colon
        case .alerts: return .alert
        case .cleanUp: return DotGlyph(rows: ["....#", "...##", ".#.##", ".####", "#####"])
        case .ports: return DotGlyph(rows: ["####.", "#...#", "####.", "#....", "#...."])
        case .integrations: return .prompt
        case .about: return .question
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: ServerMonitor
    @State private var pane: SettingsPane?

    init(monitor: ServerMonitor, initialPane: SettingsPane = .general) {
        self.monitor = monitor
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                HStack(spacing: 10) {
                    DotGridView(glyph: pane.glyph, size: 16)
                    Text(pane.rawValue).font(Theme.body)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .alerts: AlertsPane()
                case .cleanUp: CleanUpPane()
                case .ports: PortsPane(monitor: monitor)
                case .integrations: IntegrationsPane()
                case .about: AboutPane()
                }
            }
            .formStyle(.grouped)
            .font(Theme.body)
            .navigationTitle(pane?.rawValue ?? "Settings")
        }
        .frame(width: 740, height: 560)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.colonCount.rawValue
    @AppStorage(Preferences.editor) private var editor = "auto"
    @AppStorage(Preferences.terminal) private var terminal = "com.apple.Terminal"
    @AppStorage(Preferences.hotkey) private var hotkey = true
    @AppStorage(Preferences.scanInterval) private var scanInterval = 2.0
    @AppStorage(Preferences.shareUsage) private var shareUsage = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker(selection: $iconStyle) {
                    ForEach(Preferences.IconStyle.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                } label: {
                    SettingLabel("Menu bar icon", caption: "Unlit dots stay hidden until there's something to show")
                }
                .pickerStyle(.segmented)
            }
            Section("Opening") {
                Picker("Open code in", selection: $editor) {
                    Text("Automatic").tag("auto")
                    ForEach(EditorLauncher.installedEditors, id: \.id) { Text($0.name).tag($0.id) }
                    Text("Finder").tag("finder")
                }
                Picker(selection: $terminal) {
                    ForEach(TerminalLauncher.installed, id: \.id) { Text($0.name).tag($0.id) }
                } label: {
                    SettingLabel("Resume sessions in", caption: "Terminal used by “Resume in Terminal”")
                }
                Toggle(isOn: $hotkey) {
                    SettingLabel("Show popover with ⌥⌘P", caption: "Global shortcut")
                }
                .onChange(of: hotkey) { _, enabled in HotKey.shared.setEnabled(enabled) }
            }
            Section("Scanning") {
                Picker("Scan every", selection: $scanInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
            }
            Section {
                Toggle(isOn: Binding(get: { shareUsage }, set: Usage.setSharing)) {
                    SettingLabel("Share anonymous usage", caption: "Once a day: that the app ran and which features you used")
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Feature names only, like Clean up or Stop. Never your servers, projects, files or anything about your Mac.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Alerts

private struct AlertsPane: View {
    @AppStorage(Preferences.thresholdGB) private var thresholdGB = 2.0
    @AppStorage(Preferences.leakWarnings) private var leakWarnings = true
    @AppStorage(Preferences.snoozeMinutes) private var snoozeMinutes = 60
    @AppStorage(Preferences.startStop) private var startStop = false

    var body: some View {
        Form {
            Section("Memory") {
                LabeledContent("Alert when a server uses more than") {
                    HStack(spacing: 6) {
                        TextField("", value: $thresholdGB, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.mono)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Stepper("", value: $thresholdGB, in: 0.5...32, step: 0.5).labelsHidden()
                        Text("GB").font(Theme.mono).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $leakWarnings) {
                    SettingLabel("Warn about leaks", caption: "Grows more than 500 MB in 10 minutes")
                }
                Picker("Snooze for", selection: $snoozeMinutes) {
                    Text("15 minutes").tag(15)
                    Text("1 hour").tag(60)
                    Text("4 hours").tag(240)
                    Text("1 day").tag(1440)
                }
            }
            Section("Activity") {
                Toggle(isOn: $startStop) {
                    SettingLabel("Server started or stopped", caption: "Off by default: dev servers restart a lot")
                }
            }
            Section {
                Button("Open Notification Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Clean up

private struct CleanUpPane: View {
    @AppStorage(Preferences.cleanUpMode) private var mode = Preferences.CleanUpMode.ask.rawValue
    @AppStorage(Preferences.cleanUpNotify) private var notify = true
    @AppStorage(Preferences.cleanUpDeletedWorktree) private var deletedWorktree = true
    @AppStorage(Preferences.cleanUpIdleHours) private var idleHours = 4
    @AppStorage(Preferences.cleanUpRunningDays) private var runningDays = 3
    @AppStorage(Preferences.forceQuitSeconds) private var forceQuitSeconds = 3.0
    @State private var protected: [String] = UserDefaults.standard.stringArray(forKey: Preferences.protectedProcesses) ?? Preferences.defaultProtected

    var body: some View {
        Form {
            Section {
                Picker(selection: $mode) {
                    ForEach(Preferences.CleanUpMode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                } label: {
                    SettingLabel("When servers qualify", caption: "Ask lists them under Clean up. Automatic stops them for you.")
                }
                .pickerStyle(.segmented)
                Toggle(isOn: $notify) {
                    SettingLabel("Send a notification", caption: "When new servers qualify, or after they're stopped automatically")
                }
            }
            Section("Suggest stopping servers that") {
                Toggle("Belong to a deleted worktree", isOn: $deletedWorktree)
                Picker(selection: $idleHours) {
                    ForEach([1, 2, 4, 8, 24], id: \.self) { Text($0 == 1 ? "1 hour" : "\($0) hours").tag($0) }
                } label: {
                    SettingLabel("Have been idle for", caption: "No CPU and no open connections")
                }
                Picker("Have been running for", selection: $runningDays) {
                    ForEach([1, 3, 7, 14], id: \.self) { Text($0 == 1 ? "1 day" : "\($0) days").tag($0) }
                }
            }
            Section("Never stop") {
                LabeledContent("Protected processes") {
                    TokenEditor(tokens: $protected)
                }
                .onChange(of: protected) { _, value in UserDefaults.standard.set(value, forKey: Preferences.protectedProcesses) }
            }
            Section("Stopping") {
                Picker(selection: $forceQuitSeconds) {
                    ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                } label: {
                    SettingLabel("Force quit after", caption: "Sends SIGTERM to the whole process tree first")
                }
            }
        }
    }
}

// MARK: - Ports & processes

private struct PortsPane: View {
    @ObservedObject var monitor: ServerMonitor
    @State private var minPort = 3000
    @State private var maxPort = 9999
    @State private var processes: [String] = []

    var body: some View {
        Form {
            Section("Ports") {
                LabeledContent("Watch ports") {
                    HStack(spacing: 6) {
                        TextField("", value: $minPort, format: .number.grouping(.never)).frame(width: 64)
                        Text("to").font(Theme.body).foregroundStyle(.secondary)
                        TextField("", value: $maxPort, format: .number.grouping(.never)).frame(width: 64)
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono)
                    .multilineTextAlignment(.trailing)
                }
                .onSubmit { commitPorts() }
            }
            Section {
                LabeledContent("Watch processes") {
                    TokenEditor(tokens: $processes)
                }
                .onChange(of: processes) { old, new in
                    Set(old).subtracting(new).forEach(monitor.removeFromAllowlist)
                    Set(new).subtracting(old).forEach(monitor.addToAllowlist)
                }
                Button("Reset to defaults") {
                    monitor.resetAllowlist()
                    processes = monitor.allowlist.sorted()
                }
            } header: {
                Text("Processes")
            } footer: {
                Text("Only servers run by these processes show up.").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            minPort = monitor.minPort
            maxPort = monitor.maxPort
            processes = monitor.allowlist.sorted()
        }
        .onDisappear(perform: commitPorts)
    }

    private func commitPorts() {
        let low = max(1, min(minPort, maxPort))
        let high = min(65535, max(minPort, maxPort))
        if low != monitor.minPort || high != monitor.maxPort { monitor.setPortRange(min: low, max: high) }
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    @AppStorage(Preferences.linkClaude) private var claude = true
    @AppStorage(Preferences.linkCodex) private var codex = true
    @AppStorage(Preferences.linkConductor) private var conductor = true
    @AppStorage(Preferences.showBranches) private var branches = true
    @AppStorage(Preferences.vercelPreviews) private var previews = false
    @AppStorage(Preferences.githubPullRequests) private var pullRequests = false

    var body: some View {
        Form {
            Section("Coding agents") {
                Toggle(isOn: $claude) {
                    SettingLabel("Claude Code", caption: ToolDetection.claude ? "Link servers to the session that started them" : "Not found in ~/.claude")
                }
                Toggle(isOn: $codex) {
                    SettingLabel("Codex", caption: ToolDetection.codex ? "Link servers to Codex threads" : "Not found in ~/.codex")
                }
                Toggle(isOn: $conductor) {
                    SettingLabel("Conductor", caption: ToolDetection.conductor ? "Show workspace names" : "Not installed")
                }
            }
            Section("Git") {
                Toggle("Show branch names", isOn: $branches)
            }
            Section {
                Toggle(isOn: $previews) {
                    SettingLabel("Vercel previews", caption: "Preview button for each branch, from Vercel's GitHub deployments")
                }
                Toggle(isOn: $pullRequests) {
                    SettingLabel("Pull requests", caption: "Show the pull request for each branch")
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text(GitHubLookup.isAvailable ? "Uses the GitHub CLI you're already signed in to." : "Needs the GitHub CLI (gh), which wasn't found.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!GitHubLookup.isAvailable)
            Section {
                Text("Agent and Git details come from local files only. The GitHub options above and app update checks use the network.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum ToolDetection {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static var claude: Bool { FileManager.default.fileExists(atPath: home + "/.claude/projects") }
    static var codex: Bool { FileManager.default.fileExists(atPath: home + "/.codex/sessions") }
    static var conductor: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.conductor.app") != nil
        || FileManager.default.fileExists(atPath: home + "/Library/Application Support/com.conductor.app") }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject private var updater = AppUpdater.shared
    private let links: [(label: String, value: String, url: String)] = [
        ("Website", "tomjohn.design", "https://www.tomjohn.design"),
        ("LinkedIn", "in/tomjohndesign", "https://www.linkedin.com/in/tomjohndesign"),
        ("X", "@tomjohndesign", "https://x.com/tomjohndesign"),
        ("GitHub", "tomjohndesign/what-the-port", "https://github.com/tomjohndesign/what-the-port"),
    ]

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    AppIconView(size: 88)
                    VStack(spacing: 4) {
                        Text("WhatThePort").font(Theme.displaySans)
                        Text(version).font(Theme.monoCaption).foregroundStyle(.secondary)
                    }
                    Text("Every dev server on your Mac, in the menu bar.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Updates") {
                if let reason = updater.unavailableReason {
                    Text(reason).foregroundStyle(.secondary)
                } else {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: updater.setAutomaticallyChecksForUpdates
                    ))
                    Toggle(isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: updater.setAutomaticallyDownloadsUpdates
                    )) {
                        SettingLabel("Download and install updates automatically", caption: "Installs when you quit. Some updates may ask to restart the app.")
                    }
                    .disabled(!updater.automaticallyChecksForUpdates)
                }
                HStack {
                    Button("Check for Updates…", action: updater.checkForUpdates)
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let date = updater.lastUpdateCheckDate {
                        Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(Theme.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ExternalLinkRow(label: "Report a bug", value: "GitHub Issues", url: FeedbackLink.issue(.bug))
                ExternalLinkRow(label: "Suggest a feature", value: "GitHub Issues", url: FeedbackLink.issue(.feature))
            } header: {
                Text("Feedback")
            } footer: {
                Text("Opens a new issue with your app and macOS versions filled in. Nothing is sent until you submit it.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                ExternalLinkRow(label: "Enjoying WTP?", value: "Tip jar", url: FeedbackLink.tip)
            } header: {
                Text("Support")
            } footer: {
                Text("WhatThePort is free and open source. If it saves you time, you can leave a tip of any amount through Stripe.")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Made by Tomjohn") {
                ForEach(links, id: \.label) { link in
                    ExternalLinkRow(label: link.label, value: link.value, url: URL(string: link.url)!)
                }
            }
        }
    }
}

/// Prefilled GitHub issue links, so reports arrive with the details needed to reproduce them.
enum FeedbackLink {
    enum Kind { case bug, feature }

    static let repository = "https://github.com/tomjohndesign/what-the-port"

    /// Redirects to the tip page (TIP_URL on the site), so it can change without an app update.
    static let tip = URL(string: "https://whattheport.dev/tip")!

    static func issue(_ kind: Kind) -> URL {
        let body: String
        let label: String
        switch kind {
        case .bug:
            label = "bug"
            body = """
            **What happened?**


            **What did you expect?**


            **Steps to reproduce**
            1.

            ---
            \(environment)
            """
        case .feature:
            label = "enhancement"
            body = """
            **What would you like WhatThePort to do?**


            **Why would it help?**


            ---
            \(environment)
            """
        }
        var components = URLComponents(string: repository + "/issues/new")!
        components.queryItems = [URLQueryItem(name: "labels", value: label), URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// App version, build, macOS version and chip. No server, project or path details.
    static var environment: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let chip = "Apple silicon"
        #else
        let chip = "Intel"
        #endif
        return "WhatThePort \(short) (\(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(chip)"
    }
}

// MARK: - Shared

/// Form row that opens a URL, with a secondary value and an outward arrow.
struct ExternalLinkRow: View {
    let label: String
    let value: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    Text(value).font(Theme.mono)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Title with an optional caption underneath, for form rows.
struct SettingLabel: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let caption {
                Text(caption).font(Theme.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The dot-grid colon on the dark app-icon squircle.
struct AppIconView: View {
    var size: CGFloat = 88

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.165, green: 0.176, blue: 0.212), Color(red: 0.067, green: 0.075, blue: 0.094)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
            .overlay(DotGridView(glyph: .colon, size: size * 0.68))
            // The app icon remains the same artwork in both appearances.
            .environment(\.colorScheme, .dark)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
    }
}

/// Editable list of process names shown as removable chips.
struct TokenEditor: View {
    @Binding var tokens: [String]
    @State private var draft = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                HStack(spacing: 6) {
                    Text(token).font(Theme.mono)
                    Button {
                        tokens.removeAll { $0 == token }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            TextField("Add…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(Theme.body)
                .lineLimit(1)
                .frame(width: 88)
                .onSubmit {
                    let value = draft.trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty, !tokens.contains(value) { tokens.append(value) }
                    draft = ""
                }
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
}

/// Wraps children onto new lines, right-aligned, like a token field.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? 320)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
