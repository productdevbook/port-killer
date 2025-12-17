import SwiftUI

struct PortForwarderSidebarContent: View {
    @Environment(AppState.self) private var appState
    @State private var discoveryManager: KubernetesDiscoveryManager?
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Dependency warning banner
                if !DependencyChecker.shared.allRequiredInstalled {
                    DependencyWarningBanner()
                }

                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Connection cards
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
                PortForwarderStatusBar()
            }
            .frame(minWidth: 350)

            // Right: Log panel
            ConnectionLogPanel(connection: selectedConnection)
                .frame(minWidth: 300)
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
}

// MARK: - Log Panel

struct ConnectionLogPanel: View {
    let connection: PortForwardConnectionState?

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let conn = connection {
                    Text("Logs: \(conn.config.name)")
                        .font(.headline)
                } else {
                    Text("Logs")
                        .font(.headline)
                }

                Spacer()

                if let conn = connection, !conn.logs.isEmpty {
                    Button {
                        conn.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Logs")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if let conn = connection {
                if conn.logs.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                        Text("No logs yet")
                            .foregroundStyle(.secondary)
                        Text("Logs will appear when the connection is active")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(conn.logs) { log in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(Self.dateFormatter.string(from: log.timestamp))
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.tertiary)

                                        Text(log.type == .portForward ? "kubectl" : "socat")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(log.type == .portForward ? .blue : .purple)
                                            .frame(width: 50, alignment: .leading)

                                        Text(log.message)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(log.isError ? .red : .primary)
                                            .textSelection(.enabled)
                                    }
                                    .id(log.id)
                                }
                            }
                            .padding(12)
                        }
                        .onChange(of: conn.logs.count) {
                            if let lastLog = conn.logs.last {
                                withAnimation {
                                    proxy.scrollTo(lastLog.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Select a connection")
                        .foregroundStyle(.secondary)
                    Text("Click on a connection to view its logs")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Dependency Warning Banner

struct DependencyWarningBanner: View {
    @State private var isInstalling = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Missing Dependencies")
                    .font(.headline)
                Text("kubectl is required for port forwarding")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Install") {
                    installDependencies()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(Color.orange)
                .frame(height: 2),
            alignment: .top
        )
    }

    private func installDependencies() {
        isInstalling = true
        Task {
            _ = await DependencyChecker.shared.checkAndInstallMissing()
            await MainActor.run { isInstalling = false }
        }
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

// MARK: - Status Bar

struct PortForwarderStatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            // Connection count
            let manager = appState.portForwardManager
            if manager.connections.isEmpty {
                Text("No connections configured")
            } else {
                Text("\(manager.connectedCount) of \(manager.connections.count) connected")
            }

            Spacer()

            // Start/Stop All buttons
            if !manager.connections.isEmpty {
                Button {
                    manager.startAll()
                } label: {
                    Text("Start All")
                }
                .buttonStyle(.bordered)
                .disabled(manager.allConnected)

                Button {
                    manager.stopAll()
                } label: {
                    Text("Stop All")
                }
                .buttonStyle(.bordered)
                .disabled(manager.connectedCount == 0)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
