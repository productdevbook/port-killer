import AppKit
import FoundationModels
import PortKillerKit
import SwiftUI

struct PortInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.ports.selectedListeners
        let inactive = model.ports.selection.compactMap { id in id.hasPrefix("inactive:") ? Int(id.dropFirst("inactive:".count)) : nil }
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
    @State private var confirmingKill = false

    var body: some View {
        let category = model.ports.category(for: port)
        let parent = model.ports.parent(of: port)
        VStack(spacing: 0) {
            header(category)
            Form {
                Section {
                    actionButtons
                }

                if model.preferences.explainProcesses {
                    ExplanationSection(port: port, category: category, parentName: parent?.name)
                }

                Section("Process") {
                    LabeledContent("PID", value: String(port.pid))
                    if let parent {
                        LabeledContent("Parent", value: "\(parent.name) (\(parent.pid))")
                    }
                    LabeledContent("User", value: port.process.user)
                    LabeledContent("Address", value: port.address)
                    if let started = port.process.startDate {
                        LabeledContent("Started") {
                            Text(started, format: .relative(presentation: .named))
                                .help(started.formatted(date: .complete, time: .standard))
                        }
                    }
                    if let path = port.process.executablePath {
                        LabeledContent("Executable") {
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
                        }
                    }
                }

                Section {
                    Text(port.process.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("Command")
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(port.process.command) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }

                Section("Label and Note") {
                    TextField("Label", text: $label, prompt: Text("Frontend dev server"))
                        .onSubmit { model.preferences.setLabel(label, for: port.port) }
                    TextField("Note", text: $note, prompt: Text("Anything worth remembering"), axis: .vertical)
                        .lineLimit(2...6)
                        .onSubmit { model.preferences.setNote(note, for: port.port) }
                    Picker("Category", selection: Binding(
                        get: { model.preferences.categoryOverride(for: port.processName) },
                        set: { model.preferences.setCategoryOverride($0, for: port.processName) }
                    )) {
                        Text("Automatic (\(ProcessCategory.detect(port.processName).rawValue))").tag(ProcessCategory?.none)
                        Divider()
                        ForEach(ProcessCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                }

                TunnelSection(port: port)
            }
            .formStyle(.grouped)
        }
        .onAppear {
            label = model.preferences.label(for: port.port) ?? ""
            note = model.preferences.note(for: port.port) ?? ""
        }
        .onDisappear {
            model.preferences.setLabel(label, for: port.port)
            model.preferences.setNote(note, for: port.port)
        }
        .confirmationDialog("Kill \(port.processName) on Port \(port.port)?", isPresented: $confirmingKill) {
            Button("Kill", role: .destructive) { kill(.graceful) }
            Button("Force Kill") { kill(.force) }
            Button("Kill Process Tree") { kill(.tree) }
            Button("Kill and Close Connections") { kill(.deep) }
        }
    }

    private func header(_ category: ProcessCategory) -> some View {
        HStack(spacing: 12) {
            ProcessIcon(process: port.process, category: category, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(port.processName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("Port \(String(port.port))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    CategoryBadge(category: category)
                    if port.isLoopbackOnly {
                        Text("Local only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var actionButtons: some View {
        let preferences = model.preferences
        let isFavorite = preferences.favorites.contains(port.port)
        let isWatching = preferences.isWatching(port.port)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                action("Open", "safari") {
                    if let url = port.localURL { NSWorkspace.shared.open(url) }
                }
                action("Copy URL", "link") {
                    if let url = port.localURL { Pasteboard.copy(url.absoluteString) }
                }
                action("Favorite", isFavorite ? "star.fill" : "star", tint: isFavorite ? .yellow : nil) {
                    preferences.toggleFavorite(port.port)
                }
                action("Watch", isWatching ? "eye.fill" : "eye", tint: isWatching ? .blue : nil) {
                    preferences.toggleWatch(port.port)
                }
            }
            Button(role: .destructive) {
                if preferences.skipKillConfirmation {
                    kill(.graceful)
                } else {
                    confirmingKill = true
                }
            } label: {
                Label(model.ports.terminating.contains(port.id) ? "Killing…" : "Kill Process", systemImage: "xmark.octagon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.ports.terminating.contains(port.id))
        }
    }

    private func action(_ title: String, _ symbol: String, tint: Color? = nil, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint ?? .primary)
                    .frame(height: 18)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .help(title)
    }

    private func kill(_ mode: KillMode) {
        Task { await model.ports.kill(port, mode: mode) }
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
                    Button {
                        explain()
                    } label: {
                        Label("What is this process?", systemImage: "apple.intelligence")
                    }
                    .buttonStyle(.borderless)
                case .working:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                case .explained(let explanation):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(explanation.summary)
                        Label(explanation.owner, systemImage: "shippingbox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(explanation.reason, systemImage: symbol(explanation.risk))
                            .font(.caption)
                            .foregroundStyle(color(explanation.risk))
                    }
                    .textSelection(.enabled)
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message).foregroundStyle(.secondary)
                        Button("Try Again") { explain() }
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Runs on this Mac. Explanations can be wrong.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .unavailable(.deviceNotEligible):
            EmptyView()
        case .unavailable:
            if let reason = explainer.unavailableReason {
                Section("Apple Intelligence") {
                    Text(reason)
                        .font(.caption)
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

private struct TunnelSection: View {
    @Environment(AppModel.self) private var model
    let port: ListeningPort

    var body: some View {
        let tunnels = model.tunnels
        let exposures = tunnels.exposuresByPort[port.port] ?? []
        Section("Sharing") {
            if let tunnel = tunnels.quickTunnel(for: port.port) {
                QuickTunnelSummary(tunnel: tunnel)
            } else if tunnels.isInstalled {
                Button {
                    tunnels.startQuickTunnel(port: port.port)
                } label: {
                    Label("Share with a Quick Tunnel", systemImage: "cloud")
                }
                .buttonStyle(.borderless)
                .help("Create a temporary public trycloudflare.com URL for this port")
            } else {
                LabeledContent("cloudflared") {
                    Button("Copy Install Command") { Pasteboard.copy(CommandLineTool.cloudflared.installCommand) }
                }
            }
            ForEach(exposures, id: \.publicURL) { exposure in
                LabeledContent(exposure.tunnelName) {
                    Button(exposure.hostname) {
                        if let url = URL(string: exposure.publicURL) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }
}

struct QuickTunnelSummary: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: color)
            VStack(alignment: .leading, spacing: 2) {
                if let url = tunnel.url {
                    Button(url.replacingOccurrences(of: "https://", with: "")) {
                        if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                    }
                    .buttonStyle(.link)
                    .lineLimit(1)
                } else {
                    Text(tunnel.status == .failed ? "Tunnel failed" : "Starting tunnel…")
                }
                if let error = tunnel.lastError, tunnel.status != .active {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let url = tunnel.url {
                Button("Copy", systemImage: "doc.on.doc") { Pasteboard.copy(url) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            Button(tunnel.status == .failed ? "Dismiss" : "Stop", systemImage: "stop.circle") {
                model.tunnels.stopQuickTunnel(tunnel)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
    }

    private var color: Color {
        switch tunnel.status {
        case .active: .green
        case .starting, .stopping: .orange
        case .failed: .red
        }
    }
}

private struct MultiplePortsSummary: View {
    @Environment(AppModel.self) private var model
    let ports: [ListeningPort]
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("\(ports.count) Ports Selected", systemImage: "square.stack.3d.up")
            } description: {
                Text(ports.map { "\($0.processName) :\($0.port)" }.joined(separator: "\n"))
                    .lineLimit(8)
            } actions: {
                Button(role: .destructive) {
                    if model.preferences.skipKillConfirmation {
                        Task { await model.ports.kill(ports) }
                    } else {
                        confirming = true
                    }
                } label: {
                    Label("Kill \(ports.count) Processes", systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .controlSize(.large)
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
                .buttonStyle(.glass)
        }
    }
}
