import SwiftUI
import ApplicationServices
import Sparkle
import LaunchAtLogin
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable var state: AppState
    @ObservedObject var updateManager: UpdateManager
    @State private var newFavoritePort = ""
    @State private var newWatchPort = ""
    @State private var watchOnStart = true
    @State private var watchOnStop = true
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        TabView {
            // General Tab
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            // Shortcuts Tab
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            // Favorites Tab
            favoritesTab
                .tabItem { Label("Favorites", systemImage: "star") }

            // Watch Tab
            watchTab
                .tabItem { Label("Watch", systemImage: "eye") }

            // Updates Tab
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }

            // About Tab
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            LaunchAtLogin.Toggle("Launch at Login")
                .toggleStyle(.switch)

            Text("Automatically start PortKiller when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text("Permissions")
                .font(.headline)

            HStack {
                Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(hasAccessibility ? .green : .red)
                Text("Accessibility")
                Spacer()
                Button(hasAccessibility ? "Granted" : "Grant") {
                    if !hasAccessibility {
                        promptAccessibility()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            hasAccessibility = AXIsProcessTrusted()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(hasAccessibility ? .green : .blue)
                .controlSize(.small)
                .disabled(hasAccessibility)
            }
            .onAppear { hasAccessibility = AXIsProcessTrusted() }

            Text(hasAccessibility ? "Global hotkey is working." : "Required for global keyboard shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                } label: {
                    Label("Open Notification Settings", systemImage: "bell")
                }
            }
            Text("Enable notifications for port watch alerts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Form {
                KeyboardShortcuts.Recorder("Toggle Main Window:", name: .toggleMainWindow)
            }
            .formStyle(.grouped)

            Text("Click on a shortcut field and press your desired key combination.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Favorites Tab

    private var favoritesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Port", text: $newFavoritePort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Add") {
                    if let p = Int(newFavoritePort), p > 0, p <= 65535 {
                        state.favorites.insert(p)
                        newFavoritePort = ""
                    }
                }
                .disabled(!isValidPort(newFavoritePort))
            }

            if state.favorites.isEmpty {
                emptyState("No favorites", "Add ports you frequently use")
            } else {
                List {
                    ForEach(Array(state.favorites).sorted(), id: \.self) { port in
                        HStack {
                            Text(String(port))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button { state.favorites.remove(port) } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }

    // MARK: - Watch Tab

    private var watchTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Port", text: $newWatchPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Toggle("Start", isOn: $watchOnStart)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Stop", isOn: $watchOnStop)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Add") {
                    if let p = Int(newWatchPort), p > 0, p <= 65535 {
                        state.watchedPorts.append(WatchedPort(port: p, notifyOnStart: watchOnStart, notifyOnStop: watchOnStop))
                        newWatchPort = ""
                    }
                }
                .disabled(!isValidPort(newWatchPort) || (!watchOnStart && !watchOnStop))
            }
            Text("Notify when port starts or stops.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.watchedPorts.isEmpty {
                emptyState("No watched ports", "Watch ports to get notifications")
            } else {
                List {
                    ForEach(state.watchedPorts) { w in
                        HStack {
                            Text(String(w.port))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Toggle("Start", isOn: Binding(
                                get: { w.notifyOnStart },
                                set: { state.updateWatch(w.port, onStart: $0, onStop: w.notifyOnStop) }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            Toggle("Stop", isOn: Binding(
                                get: { w.notifyOnStop },
                                set: { state.updateWatch(w.port, onStart: w.notifyOnStart, onStop: $0) }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            Button { state.removeWatch(w.id) } label: {
                                Image(systemName: "trash").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding()
    }

    // MARK: - Updates Tab

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Version Info
            HStack {
                Text("PortKiller")
                    .font(.headline)
                Text(AppInfo.versionString)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Check for Updates Button
            Button {
                updateManager.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updateManager.canCheckForUpdates)

            // Last Check Date
            if let lastCheck = updateManager.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Auto Update Settings
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updateManager.automaticallyChecksForUpdates },
                set: { updateManager.automaticallyChecksForUpdates = $0 }
            ))
            .toggleStyle(.switch)

            Toggle("Automatically download updates", isOn: Binding(
                get: { updateManager.automaticallyDownloadsUpdates },
                set: { updateManager.automaticallyDownloadsUpdates = $0 }
            ))
            .toggleStyle(.switch)

            Spacer()

            // GitHub Link
            HStack {
                Spacer()
                Link(destination: URL(string: AppInfo.githubReleases)!) {
                    Label("View on GitHub", systemImage: "link")
                        .font(.caption)
                }
            }
        }
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 24) {
            Spacer()

            // App Icon & Name
            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("PortKiller")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(AppInfo.versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Find and kill processes on open ports")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            // Links
            VStack(spacing: 12) {
                Link(destination: URL(string: AppInfo.githubRepo)!) {
                    HStack {
                        Image(systemName: "star")
                        Text("Star on GitHub")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)

                Link(destination: URL(string: AppInfo.githubSponsors)!) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Sponsor")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)

                Link(destination: URL(string: AppInfo.githubIssues)!) {
                    HStack {
                        Image(systemName: "ladybug")
                        Text("Report Issue")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)

                Link(destination: URL(string: AppInfo.twitterURL)!) {
                    HStack {
                        Image(systemName: "at")
                        Text("Follow on X")
                    }
                    .frame(width: 200)
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            // Copyright
            Text("Made with love by productdevbook")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    // MARK: - Helpers

    private func isValidPort(_ text: String) -> Bool {
        guard let p = Int(text) else { return false }
        return p > 0 && p <= 65535
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack {
            Spacer()
            Text(title).foregroundStyle(.secondary)
            Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private func promptAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
