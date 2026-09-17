import AppKit
import PortKillerKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: "general") {
                GeneralSettings()
            }
            Tab("Notifications", systemImage: "bell.badge", value: "notifications") {
                NotificationSettings()
            }
            Tab("Auto-Kill", systemImage: "timer", value: "autokill") {
                AutoKillSettings()
            }
            Tab("Kubernetes", systemImage: "point.3.connected.trianglepath.dotted", value: "kubernetes") {
                KubernetesSettings()
            }
            Tab("Cloudflare", systemImage: "cloud", value: "cloudflare") {
                CloudflareSettings()
            }
            Tab("Plugins", systemImage: "puzzlepiece.extension", value: "plugins") {
                PluginSettings()
            }
            Tab("About", systemImage: "info.circle", value: "about") {
                AboutSettings()
            }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var loginItem = model.loginItem
        Form {
            Section {
                Toggle("Open PortKiller at login", isOn: $loginItem.isEnabled)
                if model.loginItem.requiresApproval {
                    LabeledContent("Needs approval in System Settings") {
                        Button("Open Login Items") { model.loginItem.openSystemSettings() }
                    }
                }
                if let error = model.loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Show or hide the window") {
                    ShortcutRecorder(shortcut: $preferences.toggleWindowShortcut)
                }
            }
            Section("Ports") {
                Picker("Scan every", selection: $preferences.refreshInterval) {
                    ForEach([1, 2, 3, 5, 10, 30], id: \.self) { seconds in
                        Text(seconds == 1 ? "Second" : "\(seconds) Seconds").tag(seconds)
                    }
                }
                Toggle("Hide system processes", isOn: $preferences.hideSystemProcesses)
                Toggle("Kill without asking", isOn: $preferences.skipKillConfirmation)
                Toggle("Group menu bar ports by process", isOn: $preferences.useTreeView)
            }
            Section {
                Toggle("Explain processes with Apple Intelligence", isOn: $preferences.explainProcesses)
            } footer: {
                Text(model.explainer.unavailableReason ?? "The inspector can describe what a process is and whether it's safe to stop. Everything runs on this Mac.")
            }
            Section {
                Button("Show Welcome Screen…") {
                    model.showingOnboarding = true
                    model.show()
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.loginItem.refresh() }
    }
}

private struct NotificationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                LabeledContent("Permission") {
                    NotificationPermissionControl()
                }
            }
            Section {
                ForEach(ProcessCategory.allCases) { category in
                    Toggle(isOn: $preferences.notifyCategories.contains(category.rawValue)) {
                        Label(category.rawValue, systemImage: category.symbolName)
                    }
                }
            } header: {
                Text("New Ports")
            } footer: {
                Text("Get a notification with a Kill button when a process of these kinds starts listening. Watched ports always notify.")
            }
            Section("Port Forwards") {
                Toggle("Notify when port forwards connect or disconnect", isOn: $preferences.portForwardNotifications)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.notifier.refreshStatus() }
    }
}

private struct AutoKillSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: AutoKillRule?

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                if preferences.autoKillRules.isEmpty {
                    Text("No rules")
                        .foregroundStyle(.secondary)
                }
                ForEach($preferences.autoKillRules) { $rule in
                    HStack {
                        Toggle(isOn: $rule.isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name.isEmpty ? "Unnamed Rule" : rule.name)
                                Text(summary(rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Edit", systemImage: "pencil") { editing = rule }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        Button("Delete", systemImage: "trash") {
                            preferences.autoKillRules.removeAll { $0.id == rule.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("PortKiller stops a matching process once it has listened for longer than the rule allows. Rules are checked on every scan.")
            }
            Section {
                Button("Add Rule…") { editing = AutoKillRule(name: "New Rule") }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $editing) { rule in
            AutoKillRuleEditor(rule: rule) { saved in
                if let index = preferences.autoKillRules.firstIndex(where: { $0.id == saved.id }) {
                    preferences.autoKillRules[index] = saved
                } else {
                    preferences.autoKillRules.append(saved)
                }
            }
        }
    }

    private func summary(_ rule: AutoKillRule) -> String {
        var parts: [String] = []
        if !rule.processPattern.isEmpty { parts.append(rule.processPattern) }
        if rule.port > 0 { parts.append("port \(rule.port)") }
        parts.append("after \(rule.timeoutMinutes) min")
        return parts.joined(separator: " · ")
    }
}

private struct AutoKillRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutoKillRule
    let onSave: (AutoKillRule) -> Void

    var body: some View {
        Form {
            TextField("Name", text: $rule.name)
            Section("Match") {
                TextField("Process", text: $rule.processPattern, prompt: Text("node*, python*"))
                TextField("Port", value: $rule.port, format: .number.grouping(.never), prompt: Text("Any"))
            }
            Section("Action") {
                Stepper("Stop after \(rule.timeoutMinutes) min", value: $rule.timeoutMinutes, in: 1...1440)
                Toggle("Notify when stopping", isOn: $rule.notifyBeforeKill)
                Toggle("Enabled", isOn: $rule.isEnabled)
            }
        }
        .formStyle(.grouped)
        .safeAreaBar(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!rule.isValid)
            }
            .padding(14)
        }
        .frame(width: 400, height: 380)
    }
}

private struct KubernetesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle("Start port forwards when PortKiller opens", isOn: $preferences.portForwardAutoStart)
            }
            Section {
                CommandLineToolRow(tool: .kubectl)
            } footer: {
                Text("PortKiller looks in Homebrew, /usr/local/bin, Rancher Desktop, OrbStack and Docker Desktop.")
            }
            Section {
                CommandLineToolRow(tool: .socat)
            } footer: {
                Text("socat is only needed for proxied port forwards.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CloudflareSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Picker("Quick tunnel protocol", selection: $preferences.quickTunnelProtocol) {
                    ForEach(QuickTunnelProtocol.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Applies to new quick tunnels. Try HTTP/2 when QUIC is blocked on your network.")
            }
            Section {
                CommandLineToolRow(tool: .cloudflared)
                LabeledContent("Cloudflare account") {
                    if model.tunnels.isLoggedIn {
                        Text("Signed In")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Copy Login Command") { Pasteboard.copy("cloudflared tunnel login") }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PluginSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let plugins = model.plugins
        Form {
            Section {
                if plugins.plugins.isEmpty {
                    Text("No plugins installed")
                        .foregroundStyle(.secondary)
                }
                ForEach(plugins.plugins) { plugin in
                    Toggle(isOn: Binding(get: { plugins.isEnabled(plugin) }, set: { plugins.setEnabled($0, for: plugin) })) {
                        Label {
                            Text(plugin.manifest.name)
                            Text([plugin.manifest.version, plugin.manifest.author, plugin.manifest.summary].compactMap { $0 }.joined(separator: " · "))
                        } icon: {
                            Image(systemName: plugin.manifest.icon ?? "puzzlepiece.extension")
                        }
                    }
                }
            } header: {
                Text("Installed Plugins")
            } footer: {
                Text("Plugins run on this Mac with your user account. Turn on only plugins you trust.")
            }
            if !plugins.failures.isEmpty {
                Section("Couldn't Load") {
                    ForEach(plugins.failures) { failure in
                        LabeledContent {
                            Text(failure.message)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label(failure.bundleURL.lastPathComponent, systemImage: "exclamationmark.triangle")
                        }
                    }
                }
            }
            Section {
                TrailingButtons {
                    if let url = AppInfo.pluginGuide {
                        Link("Build a Plugin", destination: url)
                    }
                    Spacer()
                    Button("Reload") { plugins.reload() }
                    Button("Open Plugins Folder") { plugins.openFolder() }
                }
            } footer: {
                Text("Put .portkillerplugin folders in ~/Library/Application Support/PortKiller/Plugins.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { plugins.reload() }
    }
}

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var updater = model.updater
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PortKiller")
                            .font(.title2.weight(.semibold))
                        Text("Version \(AppInfo.version) (\(AppInfo.build))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Updates") {
                LabeledContent("Last checked") {
                    if let lastCheck = model.updater.lastCheck {
                        Text(lastCheck, format: .relative(presentation: .named))
                    } else {
                        Text("Never")
                    }
                }
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                    .disabled(!model.updater.isAvailable)
                Toggle("Download updates automatically", isOn: $updater.automaticallyDownloads)
                    .disabled(!model.updater.isAvailable)
                Button("Check for Updates…") { model.updater.checkForUpdates() }
                    .disabled(!model.updater.canCheckForUpdates)
            }
            Section("Sponsors") {
                Picker("Show the sponsors page", selection: $preferences.sponsorInterval) {
                    ForEach(SponsorDisplayInterval.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("Show Sponsors") { model.showSponsors() }
            }
            Section {
                link("PortKiller on GitHub", AppInfo.repository)
                link("Report an Issue", AppInfo.issues)
                link("Sponsor productdevbook", AppInfo.sponsors)
                link("@productdevbook on X", AppInfo.twitter)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func link(_ title: String, _ url: URL?) -> some View {
        if let url {
            Link(destination: url) {
                LabeledContent(title) {
                    Image(systemName: "arrow.up.forward")
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
