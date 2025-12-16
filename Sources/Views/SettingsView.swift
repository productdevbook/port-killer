import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var newFavoritePort = ""
    @State private var newWatchPort = ""
    @State private var watchOnStart = true
    @State private var watchOnStop = true
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        TabView {
            // General Tab
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
                    .toggleStyle(.switch)
                    .onAppear { hasAccessibility = AXIsProcessTrusted() }
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
                        if hasAccessibility {
                            // Already granted, just refresh
                            hasAccessibility = AXIsProcessTrusted()
                        } else {
                            promptAccessibility()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                hasAccessibility = AXIsProcessTrusted()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hasAccessibility ? .green : .blue)
                    .controlSize(.small)
                }
                Text(hasAccessibility ? "Global hotkey is working." : "Required for ⌘⇧P hotkey. Click Grant to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            .tabItem { Label("General", systemImage: "gear") }

            // Favorites Tab
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
            .tabItem { Label("Favorites", systemImage: "star") }

            // Watch Tab
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
            .tabItem { Label("Watch", systemImage: "eye") }
        }
        .frame(width: 350, height: 380)
    }

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
    // kAXTrustedCheckOptionPrompt value is "AXTrustedCheckOptionPrompt"
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
