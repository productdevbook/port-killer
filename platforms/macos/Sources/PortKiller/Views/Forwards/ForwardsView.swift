import AppKit
import PortKillerKit
import SwiftUI

struct ForwardsView: View {
    @Environment(AppModel.self) private var model
    @State private var browsing = false

    var body: some View {
        @Bindable var forwards = model.forwards
        let sessions = forwards.sessions
        List(selection: $forwards.selection) {
            if model.preferences.locate(.kubectl) == nil {
                Section {
                    MissingToolBanner(tool: .kubectl, message: "Port forwarding runs kubectl port-forward for you.")
                }
            }
            Section {
                ForEach(sessions) { session in
                    ForwardRow(session: session)
                        .tag(session.id)
                }
                .reorderable()
            } header: {
                if let context = forwards.context {
                    Label("Context: \(context)", systemImage: "circle.hexagongrid")
                }
            }
        }
        .reorderContainer(for: PortForwardSession.self) { difference in
            let destination: PortForwardSession.ID? = switch difference.destination.position {
            case .before(let id): id
            case .end: nil
            }
            forwards.move(difference.sources, before: destination)
        }
        .contextMenu(forSelectionType: PortForwardSession.ID.self) { ids in
            if let id = ids.first, let session = sessions.first(where: { $0.id == id }) {
                ForwardActions(session: session)
            }
        } primaryAction: { ids in
            guard let id = ids.first, let session = sessions.first(where: { $0.id == id }) else { return }
            session.isActive ? session.stop() : session.start()
        }
        .onDeleteCommand {
            if let id = forwards.selection { forwards.remove(id) }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Port Forwards", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Forward a Kubernetes service to a port on this Mac. PortKiller keeps it connected.")
                } actions: {
                    Button("Browse Cluster…") { browsing = true }
                        .buttonStyle(.glassProminent)
                    Button("Add Manually") { forwards.add(.placeholder()) }
                        .buttonStyle(.glass)
                }
            }
        }
        .navigationTitle("Port Forwards")
        .navigationSubtitle(sessions.isEmpty ? "" : "\(forwards.connectedCount) of \(sessions.count) connected")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Browse Cluster…", systemImage: "square.stack.3d.down.forward") { browsing = true }
                        .disabled(model.preferences.locate(.kubectl) == nil)
                    Button("Add Manually", systemImage: "plus") { forwards.add(.placeholder()) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add a port forward")

                Button("Start All", systemImage: "play.fill") { forwards.startAll() }
                    .disabled(sessions.isEmpty)
                    .help("Start every enabled port forward")
                Button("Stop All", systemImage: "stop.fill") { forwards.stopAll() }
                    .disabled(forwards.activeCount == 0)
                    .help("Stop every port forward")
            }
            ToolbarItem {
                Button("Kill Stuck Processes", systemImage: "bandage") {
                    Task { await forwards.killStuckProcesses() }
                }
                .disabled(forwards.isKillingStuckProcesses)
                .help("Force-quit leftover kubectl port-forward and socat processes")
            }
        }
        .sheet(isPresented: $browsing) {
            ServiceBrowser()
        }
        .task {
            await forwards.refreshContext()
        }
    }
}

struct ForwardRow: View {
    let session: PortForwardSession

    var body: some View {
        let configuration = session.configuration
        HStack(spacing: 10) {
            StatusDot(color: session.status.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(configuration.name)
                        .fontWeight(.medium)
                    if !configuration.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(configuration.target)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("localhost:\(String(configuration.effectivePort))")
                    .font(.callout.monospacedDigit())
                Text(session.status.title)
                    .font(.caption)
                    .foregroundStyle(session.status.tint)
            }
            Button {
                session.isActive ? session.stop() : session.start()
            } label: {
                Image(systemName: session.isActive ? "stop.fill" : "play.fill")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(session.isActive ? "Stop" : "Start")
        }
        .padding(.vertical, 4)
    }
}

struct ForwardActions: View {
    @Environment(AppModel.self) private var model
    let session: PortForwardSession

    var body: some View {
        if session.isActive {
            Button("Stop", systemImage: "stop.fill") { session.stop() }
            Button("Restart", systemImage: "arrow.clockwise") { session.restart() }
        } else {
            Button("Start", systemImage: "play.fill") { session.start() }
        }
        Divider()
        if let url = URL(string: "http://localhost:\(session.configuration.effectivePort)") {
            Button("Open in Browser", systemImage: "safari") { NSWorkspace.shared.open(url) }
            Button("Copy URL", systemImage: "link") { Pasteboard.copy(url.absoluteString) }
        }
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") {
            var copy = session.configuration
            copy.id = UUID()
            copy.name += " Copy"
            model.forwards.add(copy)
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.forwards.remove(session.id)
        }
    }
}

struct MissingToolBanner: View {
    @Environment(AppModel.self) private var model
    let tool: CommandLineTool
    let message: String

    var body: some View {
        let installer = model.installer
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tool.name) isn't installed")
                    .fontWeight(.semibold)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let error = installer.errors[tool.name] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            Spacer()
            if installer.installing.contains(tool.name) {
                ProgressView().controlSize(.small)
            } else if installer.canInstall {
                Button("Install") { installer.install(tool) }
                    .buttonStyle(.glassProminent)
            } else {
                Button("Copy Command") { Pasteboard.copy(tool.installCommand) }
                    .buttonStyle(.glass)
            }
        }
        .padding(.vertical, 6)
    }
}

extension PortForwardSession.Status {
    var title: String {
        switch self {
        case .stopped: "Stopped"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .waitingToReconnect: "Reconnecting…"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .stopped: .secondary
        case .connecting, .waitingToReconnect, .stopping: .orange
        case .connected: .green
        case .failed: .red
        }
    }
}
