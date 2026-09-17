import PortKillerKit
import SwiftUI

struct ForwardsView: View {
    @Environment(AppModel.self) private var model
    @State private var browsing = false

    var body: some View {
        @Bindable var model = model
        let forwards = model.forwards
        let query = model.ports.filter.searchText.trimmingCharacters(in: .whitespaces)
        let sessions = forwards.sessions.filter { $0.matches(query) }
        let hasKubectl = model.preferences.locate(.kubectl) != nil

        Table(sessions, selection: $model.forwardSelection) {
            TableColumn("Status") { session in
                HStack(spacing: 6) {
                    StatusDot(color: session.status.tint)
                    Text(session.configuration.isEnabled || session.isActive ? session.status.title : "Disabled")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 120)

            TableColumn("Name") { session in
                Text(session.configuration.name)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Service") { session in
                Text(session.configuration.target)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 220)

            TableColumn("Local Address") { session in
                Text(verbatim: "localhost:\(session.configuration.effectivePort)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 130)
        }
        .contextMenu(forSelectionType: PortForwardSession.ID.self) { ids in
            if ids.count == 1, let session = forwards.sessions.first(where: { ids.contains($0.id) }) {
                ForwardActions(session: session)
            }
        } primaryAction: { _ in
            model.inspectorVisible = true
        }
        .onDeleteCommand {
            for id in model.forwardSelection { forwards.remove(id) }
            model.forwardSelection = []
        }
        .overlay {
            if forwards.sessions.isEmpty {
                ContentUnavailableView {
                    Label("No Port Forwards", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text(hasKubectl ? "Forward a Kubernetes service to a port on this Mac. PortKiller keeps it connected." : "Port forwarding runs kubectl port-forward, which isn't installed.")
                } actions: {
                    if hasKubectl {
                        Button("Browse Cluster…") { browsing = true }
                        Button("New Port Forward") { model.addForward(.placeholder()) }
                    } else {
                        ToolInstallButton(tool: .kubectl)
                    }
                }
            } else if sessions.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationSubtitle(forwards.sessions.isEmpty ? "" : "\(forwards.connectedCount) of \(forwards.sessions.count) connected")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Browse Cluster…", systemImage: "square.stack.3d.down.forward") { browsing = true }
                        .disabled(!hasKubectl)
                    Button("New Port Forward", systemImage: "plus") { model.addForward(.placeholder()) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add a port forward")
            }
            ToolbarItem {
                ForwardControlButton()
            }
            ToolbarItem {
                Menu {
                    Button("Start All", systemImage: "play") { forwards.startAll() }
                        .disabled(forwards.sessions.isEmpty)
                    Button("Stop All", systemImage: "stop") { forwards.stopAll() }
                        .disabled(forwards.activeCount == 0)
                    Divider()
                    Button("Kill Stuck Processes", systemImage: "bandage") {
                        Task { await forwards.killStuckProcesses() }
                    }
                    .disabled(forwards.isKillingStuckProcesses)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .help("Start, stop or clean up all port forwards")
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

private struct ForwardControlButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = model.forwards.sessions.filter { model.forwardSelection.contains($0.id) }
        let isActive = selected.contains(where: \.isActive)
        Button(isActive ? "Stop" : "Start", systemImage: isActive ? "stop.fill" : "play.fill") {
            for session in selected {
                isActive ? session.stop() : session.start()
            }
        }
        .disabled(selected.isEmpty)
        .help(isActive ? "Stop the selected port forwards" : "Start the selected port forwards")
    }
}

struct ForwardActions: View {
    @Environment(AppModel.self) private var model
    let session: PortForwardSession

    var body: some View {
        if session.isActive {
            Button("Stop", systemImage: "stop") { session.stop() }
            Button("Restart", systemImage: "arrow.clockwise") { session.restart() }
        } else {
            Button("Start", systemImage: "play") { session.start() }
        }
        Divider()
        if let url = session.configuration.localURL {
            URLActions(url: url)
        }
        Divider()
        Button("Duplicate", systemImage: "plus.square.on.square") {
            var copy = session.configuration
            copy.id = UUID()
            copy.name += " Copy"
            model.addForward(copy)
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.forwardSelection.remove(session.id)
            model.forwards.remove(session.id)
        }
    }
}

private extension PortForwardSession {
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [configuration.name, configuration.namespace, configuration.service, String(configuration.effectivePort)]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
