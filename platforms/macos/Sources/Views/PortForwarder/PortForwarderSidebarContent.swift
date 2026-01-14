import SwiftUI

struct PortForwarderSidebarContent: View {
    @Environment(AppState.self) private var appState
    @State private var discoveryManager: KubernetesDiscoveryManager?
    @State private var searchText = ""
    @State private var groupByNamespace = true

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            PortForwarderToolbar(
                searchText: $searchText,
                groupByNamespace: $groupByNamespace,
                discoveryManager: $discoveryManager
            )

            Divider()

            // Dependency warning banner
            if !DependencyChecker.shared.allRequiredInstalled {
                DependencyWarningBanner()
            }

            // Table header
            PortForwarderTableHeader()

            Divider()

            // Main content - Table
            if filteredConnections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if groupByNamespace {
                            groupedView
                        } else {
                            flatView
                        }
                    }
                }
            }

            Divider()

            // Status bar
            PortForwarderStatusBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $discoveryManager) { dm in
            ServiceBrowserView(
                discoveryManager: dm,
                onServiceSelected: { config in
                    appState.portForwardManager.addConnection(config)
                    discoveryManager = nil
                },
                onCancel: {
                    discoveryManager = nil
                }
            )
        }
    }

    // MARK: - Filtered Connections

    private var filteredConnections: [PortForwardConnectionState] {
        let connections = appState.portForwardManager.connections
        guard !searchText.isEmpty else { return connections }
        return connections.filter { conn in
            conn.config.name.localizedCaseInsensitiveContains(searchText) ||
            conn.config.namespace.localizedCaseInsensitiveContains(searchText) ||
            conn.config.service.localizedCaseInsensitiveContains(searchText) ||
            String(conn.effectivePort).contains(searchText)
        }
    }

    private var connectionsByNamespace: [(namespace: String, connections: [PortForwardConnectionState])] {
        let grouped = Dictionary(grouping: filteredConnections) { $0.config.namespace }
        return grouped.map { (namespace: $0.key, connections: $0.value) }
            .sorted { $0.namespace < $1.namespace }
    }

    // MARK: - Views

    @ViewBuilder
    private var groupedView: some View {
        ForEach(connectionsByNamespace, id: \.namespace) { group in
            // Namespace header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text(group.namespace)
                    .font(.caption.weight(.semibold))
                Text("(\(group.connections.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            ForEach(group.connections) { connection in
                PortForwarderTableRow(
                    connection: connection,
                    isSelected: appState.selectedPortForwardConnectionId == connection.id,
                    onSelect: { appState.selectedPortForwardConnectionId = connection.id }
                )
            }
        }
    }

    @ViewBuilder
    private var flatView: some View {
        ForEach(filteredConnections) { connection in
            PortForwarderTableRow(
                connection: connection,
                isSelected: appState.selectedPortForwardConnectionId == connection.id,
                onSelect: { appState.selectedPortForwardConnectionId = connection.id }
            )
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Connections", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            if searchText.isEmpty {
                Text("Add a connection or import from Kubernetes")
            } else {
                Text("No connections match '\(searchText)'")
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Add Connection Buttons

struct AddConnectionButtons: View {
    @Environment(AppState.self) private var appState
    @Binding var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        HStack(spacing: 16) {
            // Manual add button
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
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Connection")
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            // Import from Kubernetes button
            Button {
                let dm = KubernetesDiscoveryManager(processManager: appState.portForwardManager.processManager)
                Task { await dm.loadNamespaces() }
                discoveryManager = dm
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import from Kubernetes")
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(!DependencyChecker.shared.allRequiredInstalled)
        }
        .padding(.top, 4)
    }
}
