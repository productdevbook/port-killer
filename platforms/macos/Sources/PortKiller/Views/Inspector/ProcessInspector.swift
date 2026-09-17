import AppKit
import FoundationModels
import PortKillerKit
import SwiftUI

struct ProcessInfoInspector: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem
    @State private var parent: ProcessSnapshot?

    var body: some View {
        let process = item.process
        Form {
            Section("Process") {
                InfoRow(title: "Name", value: process.name)
                InfoRow(title: "PID", value: String(process.pid))
                if let parent {
                    InfoRow(title: "Parent", value: "\(parent.name) (\(parent.pid))")
                }
                InfoRow(title: "User", value: process.user)
                InfoRow(title: "Category", value: item.category.rawValue)
                if let started = process.startDate {
                    InfoRow(title: "Started", value: started.formatted(date: .abbreviated, time: .shortened))
                }
                if let path = process.executablePath {
                    InfoRow(title: "Executable", value: path)
                }
            }
            Section("Ports") {
                ForEach(item.ports) { port in
                    InfoRow(title: String(port.port), value: port.isLoopbackOnly ? "\(port.address) · This Mac only" : port.address)
                }
            }
            Section("Command") {
                Text(process.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TrailingButtons {
                    Button("Copy Command") { Pasteboard.copy(process.command) }
                }
            }
            if model.preferences.explainProcesses {
                ExplanationSection(port: item.ports[0], category: item.category, parentName: parent?.name)
            }
        }
        .formStyle(.grouped)
        .task(id: process.pid) {
            model.explainer.refreshAvailability()
            parent = nil
            parent = await model.ports.parent(of: process)
        }
    }
}

struct ProcessSettingsInspector: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        let preferences = model.preferences
        Form {
            ForEach(model.focusedPorts(in: item)) { port in
                PortSettingsSection(port: port.port)
                    .id(port.port)
            }
            Section {
                Picker(selection: Binding(
                    get: { preferences.categoryOverride(for: item.process.name) },
                    set: { preferences.setCategoryOverride($0, for: item.process.name) }
                )) {
                    Text("Automatic (\(ProcessCategory.detect(item.process.name).rawValue))").tag(ProcessCategory?.none)
                    Divider()
                    ForEach(ProcessCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                } label: {
                    Label("Category", systemImage: "square.grid.2x2")
                }
            } header: {
                Text(item.process.name)
            } footer: {
                Text("The category applies to every process named \(item.process.name).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PortSettingsSection: View {
    @Environment(AppModel.self) private var model
    let port: Int
    @State private var label = ""
    @State private var note = ""

    var body: some View {
        let preferences = model.preferences
        Section("Port \(String(port))") {
            Toggle(isOn: Binding(get: { preferences.favorites.contains(port) }, set: { _ in preferences.toggleFavorite(port) })) {
                Label("Favorite", systemImage: "star")
            }
            Toggle(isOn: Binding(get: { preferences.isWatching(port) }, set: { _ in preferences.toggleWatch(port) })) {
                Label("Notify on Start and Stop", systemImage: "eye")
            }
            TextField(text: $label, prompt: Text("Frontend dev server")) {
                Label("Label", systemImage: "tag")
            }
            .onSubmit { preferences.setLabel(label, for: port) }
            TextField(text: $note, prompt: Text("Anything worth remembering"), axis: .vertical) {
                Label("Note", systemImage: "note.text")
            }
            .lineLimit(1...5)
            .onSubmit { preferences.setNote(note, for: port) }
        }
        .onAppear {
            label = preferences.label(for: port) ?? ""
            note = preferences.note(for: port) ?? ""
        }
        .onDisappear {
            preferences.setLabel(label, for: port)
            preferences.setNote(note, for: port)
        }
    }
}

struct InactivePortInspector: View {
    @Environment(AppModel.self) private var model
    let port: Int

    var body: some View {
        Form {
            PortSettingsSection(port: port)
                .id(port)
        }
        .formStyle(.grouped)
    }
}

struct ProcessSharingInspector: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        let tunnels = model.tunnels
        Form {
            if !tunnels.isInstalled {
                Section {
                    ToolNotice(tool: .cloudflared, message: "Share ports on a public URL.")
                }
            }
            ForEach(model.focusedPorts(in: item)) { port in
                Section("Port \(String(port.port))") {
                    if let tunnel = tunnels.quickTunnel(for: port.port) {
                        LabeledContent {
                            if let url = tunnel.url {
                                Link(tunnel.host ?? url.absoluteString, destination: url)
                                    .lineLimit(1)
                            } else {
                                Text(tunnel.status.title)
                            }
                        } label: {
                            Label("Quick Tunnel", systemImage: "bolt")
                        }
                        if let error = tunnel.lastError, tunnel.status != .active {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                        }
                        TrailingButtons {
                            Button("Show") { model.selection = .quickTunnel(tunnel.id) }
                            Button(tunnel.status == .failed ? "Dismiss" : "Stop") { tunnels.stopQuickTunnel(tunnel) }
                        }
                    } else {
                        TrailingButtons {
                            Button("Share with Quick Tunnel") { tunnels.startQuickTunnel(port: port.port) }
                                .disabled(!tunnels.isInstalled)
                        }
                    }
                    ForEach(tunnels.exposuresByPort[port.port] ?? [], id: \.publicURL) { exposure in
                        LabeledContent {
                            if let url = URL(string: exposure.publicURL) {
                                Link(exposure.hostname, destination: url)
                            } else {
                                Text(exposure.hostname)
                            }
                        } label: {
                            Label(exposure.tunnelName, systemImage: "cloud")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ProcessPluginsInspector: View {
    @Environment(AppModel.self) private var model
    let item: ProcessItem

    var body: some View {
        let entries = model.focusedPorts(in: item).flatMap { port in model.plugins.portActions(for: port).map { (port: port, plugin: $0.plugin, action: $0.action) } }
        if entries.isEmpty {
            ContentUnavailableView {
                Label("No Plugin Actions", systemImage: InspectorTab.plugins.symbol)
            } description: {
                Text("Plugins can add actions for ports like this one. Turn plugins on in Settings.")
            } actions: {
                if let url = AppInfo.pluginGuide {
                    Link("Build a Plugin", destination: url)
                }
            }
        } else {
            Form {
                ForEach(model.focusedPorts(in: item)) { port in
                    let actions = entries.filter { $0.port == port }
                    if !actions.isEmpty {
                        Section("Port \(String(port.port))") {
                            ForEach(Array(actions.enumerated()), id: \.offset) { _, entry in
                                LabeledContent {
                                    Button("Run") {
                                        Task { await model.plugins.perform(entry.action, on: port, in: entry.plugin) }
                                    }
                                } label: {
                                    Label {
                                        Text(entry.action.title)
                                        Text(entry.plugin.manifest.name)
                                    } icon: {
                                        Image(systemName: entry.action.icon ?? entry.plugin.manifest.icon ?? "puzzlepiece.extension")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ExplanationSection: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    let category: ProcessCategory
    let parentName: String?

    var body: some View {
        let explainer = model.explainer
        switch explainer.availability {
        case .available:
            Section {
                switch explainer.state(for: port) {
                case .idle:
                    TrailingButtons {
                        Button("Explain This Process", systemImage: "apple.intelligence") { explain() }
                    }
                case .working:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                case .explained(let explanation):
                    Text(explanation.summary)
                        .textSelection(.enabled)
                    InfoRow(title: "Belongs To", value: explanation.owner)
                    Label(explanation.reason, systemImage: symbol(explanation.risk))
                        .foregroundStyle(color(explanation.risk))
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                    TrailingButtons {
                        Button("Try Again") { explain() }
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Runs on this Mac. Explanations can be wrong.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .unavailable(.deviceNotEligible):
            EmptyView()
        case .unavailable:
            if let reason = explainer.unavailableReason {
                Section("Apple Intelligence") {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func explain() {
        Task { await model.explainer.explain(port, category: category, parentName: parentName) }
    }

    private func symbol(_ risk: ProcessExplanation.Risk) -> String {
        switch risk {
        case .safe: "checkmark.shield"
        case .caution: "exclamationmark.triangle"
        case .avoid: "hand.raised"
        }
    }

    private func color(_ risk: ProcessExplanation.Risk) -> Color {
        switch risk {
        case .safe: .green
        case .caution: .orange
        case .avoid: .red
        }
    }
}
