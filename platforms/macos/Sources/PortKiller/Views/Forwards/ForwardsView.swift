import PortKillerKit
import SwiftUI

struct ForwardsView: View {
    @Environment(AppModel.self) private var model
    @State private var browsing = false

    var body: some View {
        @Bindable var forwards = model.forwards
        let sessions = forwards.sessions
        let hasKubectl = model.preferences.locate(.kubectl) != nil
        List(selection: $forwards.selection) {
            if !hasKubectl {
                Section {
                    ToolNotice(tool: .kubectl, message: "Port forwarding runs kubectl port-forward for you.")
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
                    Label(context, systemImage: "circle.hexagongrid")
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
            session.toggle()
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
                    Button("Add Manually") { forwards.add(.placeholder()) }
                }
            }
        }
        .navigationTitle("Port Forwards")
        .navigationSubtitle(sessions.isEmpty ? "" : "\(forwards.connectedCount) of \(sessions.count) connected")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Browse Cluster…", systemImage: "square.stack.3d.down.forward") { browsing = true }
                        .disabled(!hasKubectl)
                    Button("Add Manually", systemImage: "plus") { forwards.add(.placeholder()) }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
                .help("Add a port forward")

                Button("Start All", systemImage: "play") { forwards.startAll() }
                    .disabled(sessions.isEmpty)
                    .help("Start every enabled port forward")
                Button("Stop All", systemImage: "stop") { forwards.stopAll() }
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

private struct ForwardRow: View {
    let session: PortForwardSession

    var body: some View {
        let configuration = session.configuration
        HStack(spacing: 10) {
            RowIcon(symbol: "point.3.connected.trianglepath.dotted", tint: session.status.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(configuration.name)
                    .lineLimit(1)
                Text("\(configuration.target) · \(configuration.isEnabled ? session.status.title : "Disabled")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(verbatim: ":\(configuration.effectivePort)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(configuration.isEnabled || session.isActive ? 1 : 0.55)
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
            model.forwards.add(copy)
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
            model.forwards.remove(session.id)
        }
    }
}
