import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var monitor: PortMonitor
    @AppStorage("minPort") private var minPort: Int = 3000
    @AppStorage("maxPort") private var maxPort: Int = 9999

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PortRangeTab(minPort: $minPort, maxPort: $maxPort, monitor: monitor)
                .tabItem {
                    Label("Ports", systemImage: "number")
                }

            ProcessesTab(monitor: monitor)
                .tabItem {
                    Label("Processes", systemImage: "list.bullet")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 350)
    }
}

struct GeneralTab: View {
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
                            launchAtLogin = !newValue
                        }
                    }
                Text("Automatically start WhatThePort when you log in")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct PortRangeTab: View {
    @Binding var minPort: Int
    @Binding var maxPort: Int
    @ObservedObject var monitor: PortMonitor

    var body: some View {
        Form {
            Section("Port Range") {
                HStack {
                    Text("From:")
                    TextField("Min", value: $minPort, format: .number)
                        .frame(width: 80)
                    Text("To:")
                    TextField("Max", value: $maxPort, format: .number)
                        .frame(width: 80)
                }
                Text("Only show ports within this range")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onChange(of: minPort) { _, newValue in
            monitor.minPort = newValue
            monitor.scan()
        }
        .onChange(of: maxPort) { _, newValue in
            monitor.maxPort = newValue
            monitor.scan()
        }
        .onAppear {
            monitor.minPort = minPort
            monitor.maxPort = maxPort
        }
    }
}

struct ProcessesTab: View {
    @ObservedObject var monitor: PortMonitor
    @State private var newProcess: String = ""

    var sortedAllowlist: [String] {
        monitor.allowlist.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allowed Processes")
                .font(.headline)

            Text("Only these process names will be shown in the menu")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                TextField("Add process name...", text: $newProcess)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let trimmed = newProcess.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        monitor.addToAllowlist(trimmed)
                        newProcess = ""
                    }
                }
                .disabled(newProcess.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(sortedAllowlist, id: \.self) { process in
                    HStack {
                        Text(process)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            monitor.removeFromAllowlist(process)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.bordered)

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    monitor.resetAllowlist()
                }
            }
        }
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "network")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("WhatThePort")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text("A simple menu bar app to monitor local development servers and the ports they're running on.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Text("Created by Tomjohn")
                    .font(.headline)
                    .padding(.top, 8)

                HStack(spacing: 16) {
                    Link("Website", destination: URL(string: "https://www.tomjohn.design")!)
                    Link("LinkedIn", destination: URL(string: "https://www.linkedin.com/in/tomjohndesign")!)
                    Link("X", destination: URL(string: "https://x.com/tomjohndesign")!)
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
