import SwiftUI

struct ConnectionsTab: View {
    @Environment(AppState.self) private var appState
    @Binding var discoveryManager: KubernetesDiscoveryManager?
    @State private var selectedConnectionId: UUID?

    private var selectedConnection: PortForwardConnectionState? {
        guard let id = selectedConnectionId else { return nil }
        return appState.portForwardManager.connections.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // Left: Connection list
            VStack(spacing: 0) {
                // Header with action buttons
                HStack {
                    Text("Connections")
                        .font(.headline)

                    Spacer()

                    Button {
                        let config = PortForwardConnectionConfig(
                            name: "New Connection",
                            namespace: "default",
                            service: "service-name",
                            localPort: 8080,
                            remotePort: 80
                        )
                        appState.portForwardManager.addConnection(config)
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Add Connection")

                    Button {
                        let dm = KubernetesDiscoveryManager(processManager: appState.portForwardManager.processManager)
                        Task { await dm.loadNamespaces() }
                        discoveryManager = dm
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!DependencyChecker.shared.allRequiredInstalled)
                    .help("Import from Kubernetes")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // Dependency warning
                if !DependencyChecker.shared.allRequiredInstalled {
                    DependencyWarningBanner()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.portForwardManager.connections) { connection in
                            PortForwardConnectionCard(
                                connection: connection,
                                isSelected: selectedConnectionId == connection.id,
                                onSelect: { selectedConnectionId = connection.id }
                            )
                        }
                    }
                    .padding(16)
                }

                Divider()

                // Status bar
                HStack {
                    let manager = appState.portForwardManager
                    if manager.connections.isEmpty {
                        Text("No connections configured")
                    } else {
                        Text("\(manager.connectedCount) of \(manager.connections.count) connected")
                    }

                    Spacer()

                    if manager.isKillingProcesses {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Killing processes...")
                            .foregroundStyle(.secondary)
                    } else if !manager.connections.isEmpty {
                        Button("Kill All Stuck") {
                            Task { await manager.killStuckProcesses() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Start All") {
                            manager.startAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.allConnected)

                        Button("Stop All") {
                            manager.stopAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.connectedCount == 0)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 400)

            // Right: Log viewer
            ConnectionLogPanel(connection: selectedConnection)
                .frame(minWidth: 450)
        }
    }
}
