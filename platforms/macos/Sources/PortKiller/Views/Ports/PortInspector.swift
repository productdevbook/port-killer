import AppKit
import FoundationModels
import PortKillerKit
import SwiftUI

struct PortInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.selectedListeners
        let inactive = model.ports.selection.compactMap(\.inactivePort)
        Group {
            if selected.count == 1, let port = selected.first {
                PortDetails(port: port)
                    .id(port.id)
            } else if selected.count > 1 {
                MultiplePortsSummary(ports: selected)
            } else if let port = inactive.first {
                InactivePortDetails(port: port)
                    .id(port)
            } else {
                ContentUnavailableView("No Port Selected", systemImage: "network", description: Text("Select a port to see its process, command and actions."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PortDetails: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort
    @State private var label = ""
    @State private var note = ""
    @State private var parent: ProcessSnapshot?

    var body: some View {
        let preferences = model.preferences
        let category = model.ports.category(for: port)
        let isTerminating = model.ports.terminating.contains(port.id)
        Form {
            Section {
                LabeledContent {
                    Text("Port \(String(port.port))")
                        .monospacedDigit()
                } label: {
                    Label {
                        Text(port.processName)
                            .lineLimit(1)
                        Text(category.rawValue)
                    } icon: {
                        ProcessIcon(process: port.process, category: category, size: 20)
                    }
                }
                if let url = port.localURL {
                    LabeledContent {
                        Link(url.absoluteString, destination: url)
                    } label: {
                        Label("URL", systemImage: "link")
                    }
                    .contextMenu { URLActions(url: url) }
                }
                Toggle(isOn: Binding(get: { preferences.favorites.contains(port.port) }, set: { _ in preferences.toggleFavorite(port.port) })) {
                    Label("Favorite", systemImage: "star")
                }
                Toggle(isOn: Binding(get: { preferences.isWatching(port.port) }, set: { _ in preferences.toggleWatch(port.port) })) {
                    Label("Watch", systemImage: "eye")
                }
                TrailingButtons {
                    if isTerminating {
                        ProgressView().controlSize(.small)
                    }
                    Button("Kill Process", role: .destructive) { model.ports.requestKill([port]) }
                        .disabled(isTerminating)
                }
            } footer: {
                if port.isLoopbackOnly {
                    Text("Only reachable from this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if preferences.explainProcesses {
                ExplanationSection(port: port, category: category, parentName: parent?.name)
            }

            Section("Process") {
                value("PID", "number", String(port.pid))
                if let parent {
                    value("Parent", "arrow.turn.left.up", "\(parent.name) (\(parent.pid))")
                }
                value("User", "person", port.process.user)
                value("Address", "network", port.address)
                if let started = port.process.startDate {
                    LabeledContent {
                        Text(started, format: .relative(presentation: .named))
                            .help(started.formatted(date: .complete, time: .standard))
                    } label: {
                        Label("Started", systemImage: "clock")
                    }
                }
                if let path = port.process.executablePath {
                    LabeledContent {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                        } label: {
                            Text(path)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .multilineTextAlignment(.trailing)
                        }
                        .buttonStyle(.link)
                        .help("Show in Finder")
                    } label: {
                        Label("Executable", systemImage: "app")
                    }
                }
            }

            Section("Command") {
                Text(port.process.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TrailingButtons {
                    Button("Copy Command") { Pasteboard.copy(port.process.command) }
                }
            }

            Section("Label and Note") {
                TextField(text: $label, prompt: Text("Frontend dev server")) {
                    Label("Label", systemImage: "tag")
                }
                .onSubmit { preferences.setLabel(label, for: port.port) }
                TextField(text: $note, prompt: Text("Anything worth remembering"), axis: .vertical) {
                    Label("Note", systemImage: "note.text")
                }
                .lineLimit(2...6)
                .onSubmit { preferences.setNote(note, for: port.port) }
                Picker(selection: Binding(
                    get: { preferences.categoryOverride(for: port.processName) },
                    set: { preferences.setCategoryOverride($0, for: port.processName) }
                )) {
                    Text("Automatic (\(ProcessCategory.detect(port.processName).rawValue))").tag(ProcessCategory?.none)
                    Divider()
                    ForEach(ProcessCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                } label: {
                    Label("Category", systemImage: "square.grid.2x2")
                }
            }

            SharingSection(port: port)
        }
        .formStyle(.grouped)
        .onAppear {
            label = preferences.label(for: port.port) ?? ""
            note = preferences.note(for: port.port) ?? ""
        }
        .onDisappear {
            preferences.setLabel(label, for: port.port)
            preferences.setNote(note, for: port.port)
        }
        .task {
            parent = await model.ports.parent(of: port)
        }
    }

    private func value(_ title: String, _ symbol: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .textSelection(.enabled)
        } label: {
            Label(title, systemImage: symbol)
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
                    LabeledContent {
                        Text(explanation.owner)
                    } label: {
                        Label("Belongs To", systemImage: "shippingbox")
                    }
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

private struct SharingSection: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort

    var body: some View {
        let tunnels = model.tunnels
        Section("Sharing") {
            if let tunnel = tunnels.quickTunnel(for: port.port) {
                QuickTunnelSummary(tunnel: tunnel)
            } else if tunnels.isInstalled {
                TrailingButtons {
                    Button("Share with Quick Tunnel", systemImage: "bolt") {
                        tunnels.startQuickTunnel(port: port.port)
                    }
                    .help("Create a temporary public trycloudflare.com URL for this port")
                }
            } else {
                LabeledContent {
                    ToolInstallButton(tool: .cloudflared)
                } label: {
                    Label("cloudflared Isn't Installed", systemImage: "cloud")
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

struct QuickTunnelSummary: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        LabeledContent {
            if let url = tunnel.url {
                Link(tunnel.host ?? url.absoluteString, destination: url)
                    .lineLimit(1)
            } else {
                Text(tunnel.status.title)
            }
        } label: {
            Label {
                Text("Quick Tunnel")
            } icon: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(tunnel.status.tint)
            }
        }
        if let error = tunnel.lastError, tunnel.status != .active {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        TrailingButtons {
            if let url = tunnel.url {
                Button("Copy URL") { Pasteboard.copy(url.absoluteString) }
            }
            Button(tunnel.status == .failed ? "Dismiss" : "Stop Tunnel") {
                model.tunnels.stopQuickTunnel(tunnel)
            }
        }
    }
}

private struct MultiplePortsSummary: View {
    @Environment(AppModel.self) private var model
    let ports: [ListeningPort]
    @State private var confirming = false

    var body: some View {
        ContentUnavailableView {
            Label("\(ports.count) Ports Selected", systemImage: "square.stack.3d.up")
        } description: {
            Text(ports.map { "\($0.processName) :\($0.port)" }.joined(separator: "\n"))
                .lineLimit(8)
        } actions: {
            Button("Kill \(ports.count) Processes", role: .destructive) {
                if model.preferences.skipKillConfirmation {
                    Task { await model.ports.kill(ports) }
                } else {
                    confirming = true
                }
            }
        }
        .confirmationDialog("Kill \(ports.count) Processes?", isPresented: $confirming) {
            Button("Kill", role: .destructive) { Task { await model.ports.kill(ports) } }
            Button("Force Kill") { Task { await model.ports.kill(ports, mode: .force) } }
        }
    }
}

private struct InactivePortDetails: View {
    @Environment(AppModel.self) private var model
    let port: Int

    var body: some View {
        ContentUnavailableView {
            Label("Port \(String(port)) Is Free", systemImage: "moon.zzz")
        } description: {
            Text("Nothing listens on this port right now. PortKiller keeps it here because it's a favorite or watched.")
        } actions: {
            Button("Remove") { model.ports.removeInactive(port) }
        }
    }
}
