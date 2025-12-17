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

// MARK: - Toolbar

private struct PortForwarderToolbar: View {
    @Environment(AppState.self) private var appState
    @Binding var searchText: String
    @Binding var groupByNamespace: Bool
    @Binding var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // Group toggle
            Button {
                groupByNamespace.toggle()
            } label: {
                Image(systemName: groupByNamespace ? "folder.fill" : "list.bullet")
            }
            .buttonStyle(.bordered)
            .help(groupByNamespace ? "Show flat list" : "Group by namespace")

            Spacer()

            let manager = appState.portForwardManager

            if !manager.connections.isEmpty {
                Button {
                    manager.startAll()
                } label: {
                    Label("Start All", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(manager.allConnected)

                Button {
                    manager.stopAll()
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(manager.connectedCount == 0)

                Button {
                    Task { await manager.killStuckProcesses() }
                } label: {
                    Label("Force Stop", systemImage: "xmark.octagon.fill")
                }
                .buttonStyle(.bordered)
                .help("Kill all stuck kubectl/socat processes")
            }

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

            Button {
                let dm = KubernetesDiscoveryManager(processManager: appState.portForwardManager.processManager)
                Task { await dm.loadNamespaces() }
                discoveryManager = dm
            } label: {
                Label("Import", systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!DependencyChecker.shared.allRequiredInstalled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Table Header

private struct PortForwarderTableHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Status")
                .frame(width: 80, alignment: .leading)
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Service")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Port")
                .frame(width: 80, alignment: .leading)
            Text("Actions")
                .frame(width: 80, alignment: .center)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Table Row

private struct PortForwarderTableRow: View {
    @Environment(AppState.self) private var appState
    let connection: PortForwardConnectionState
    let isSelected: Bool
    let onSelect: () -> Void

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        }
        return .gray
    }

    private var statusText: String {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return "Error"
        } else if connection.isFullyConnected {
            return "Connected"
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return "Connecting"
        }
        return "Stopped"
    }

    private var isConnecting: Bool {
        connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            .frame(width: 80, alignment: .leading)

            // Name
            Text(connection.config.name)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Service
            Text(connection.config.service)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Port
            Text(":" + String(connection.effectivePort))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80, alignment: .leading)

            // Actions
            HStack(spacing: 4) {
                if isConnecting {
                    Button {
                        appState.portForwardManager.stopConnection(connection.id)
                    } label: {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                } else if connection.isFullyConnected {
                    Button {
                        appState.portForwardManager.stopConnection(connection.id)
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else {
                    Button {
                        appState.portForwardManager.startConnection(connection.id)
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Start")
                }

                Button {
                    appState.portForwardManager.removeConnection(connection.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            if connection.isFullyConnected {
                Button {
                    appState.portForwardManager.stopConnection(connection.id)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            } else if isConnecting {
                Button {
                    appState.portForwardManager.stopConnection(connection.id)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            } else {
                Button {
                    appState.portForwardManager.startConnection(connection.id)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
            }

            Button {
                appState.portForwardManager.restartConnection(connection.id)
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .disabled(!connection.isFullyConnected)

            Divider()

            Button(role: .destructive) {
                appState.portForwardManager.removeConnection(connection.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Detail Panel (Edit + Logs)

struct ConnectionLogPanel: View {
    @Environment(AppState.self) private var appState
    let connection: PortForwardConnectionState?
    @State private var showDetails = true

    var body: some View {
        VStack(spacing: 0) {
            if let conn = connection {
                // Edit Form Section
                ConnectionEditSection(connection: conn, isExpanded: $showDetails)

                Divider()

                // Logs Section
                ConnectionLogsSection(connection: conn)
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("Select a connection")
                        .foregroundStyle(.secondary)
                    Text("Click on a connection to view details and logs")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Edit Section

private struct ConnectionEditSection: View {
    @Environment(AppState.self) private var appState
    let connection: PortForwardConnectionState
    @Binding var isExpanded: Bool

    @State private var name: String = ""
    @State private var namespace: String = ""
    @State private var service: String = ""
    @State private var localPort: String = ""
    @State private var remotePort: String = ""
    @State private var proxyPort: String = ""
    @State private var proxyEnabled: Bool = false
    @State private var autoReconnect: Bool = true
    @State private var isEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Header with collapse toggle
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .font(.caption)
                        Text("Details")
                            .font(.headline)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if isExpanded {
                VStack(spacing: 12) {
                    // Name
                    LabeledField("Name") {
                        TextField("Connection name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Namespace & Service
                    HStack(spacing: 12) {
                        LabeledField("Namespace") {
                            TextField("default", text: $namespace)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Service") {
                            TextField("service-name", text: $service)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Ports
                    HStack(spacing: 12) {
                        LabeledField("Local Port") {
                            TextField("8080", text: $localPort)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("Remote Port") {
                            TextField("80", text: $remotePort)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Proxy
                    HStack(spacing: 12) {
                        Toggle("Proxy", isOn: $proxyEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        if proxyEnabled {
                            LabeledField("Proxy Port") {
                                TextField("8081", text: $proxyPort)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Spacer()
                    }

                    // Options
                    HStack(spacing: 16) {
                        Toggle("Auto Reconnect", isOn: $autoReconnect)
                            .toggleStyle(.checkbox)
                        Toggle("Enabled", isOn: $isEnabled)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .onAppear { loadFromConnection() }
        .onChange(of: connection.id) { loadFromConnection() }
        .onChange(of: name) { saveToConnection() }
        .onChange(of: namespace) { saveToConnection() }
        .onChange(of: service) { saveToConnection() }
        .onChange(of: localPort) { saveToConnection() }
        .onChange(of: remotePort) { saveToConnection() }
        .onChange(of: proxyPort) { saveToConnection() }
        .onChange(of: proxyEnabled) { saveToConnection() }
        .onChange(of: autoReconnect) { saveToConnection() }
        .onChange(of: isEnabled) { saveToConnection() }
    }

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        }
        return .gray
    }

    private var statusText: String {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return "Error"
        } else if connection.isFullyConnected {
            return "Connected"
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return "Connecting"
        }
        return "Stopped"
    }

    private func loadFromConnection() {
        name = connection.config.name
        namespace = connection.config.namespace
        service = connection.config.service
        localPort = String(connection.config.localPort)
        remotePort = String(connection.config.remotePort)
        proxyEnabled = connection.config.proxyPort != nil
        proxyPort = connection.config.proxyPort.map { String($0) } ?? ""
        autoReconnect = connection.config.autoReconnect
        isEnabled = connection.config.isEnabled
    }

    private func saveToConnection() {
        let newConfig = PortForwardConnectionConfig(
            id: connection.id,
            name: name,
            namespace: namespace,
            service: service,
            localPort: Int(localPort) ?? connection.config.localPort,
            remotePort: Int(remotePort) ?? connection.config.remotePort,
            proxyPort: proxyEnabled ? Int(proxyPort) : nil,
            isEnabled: isEnabled,
            autoReconnect: autoReconnect,
            useDirectExec: connection.config.useDirectExec
        )
        appState.portForwardManager.updateConnection(newConfig)
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Logs Section

private struct ConnectionLogsSection: View {
    let connection: PortForwardConnectionState

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Logs header
            HStack {
                Text("Logs")
                    .font(.headline)

                if !connection.logs.isEmpty {
                    Text("(\(connection.logs.count))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if !connection.logs.isEmpty {
                    Button {
                        ClipboardService.copyLogsAsMarkdown(connection.logs, connectionName: connection.config.name)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy All Logs (Markdown)")

                    Button {
                        connection.clearLogs()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear Logs")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if connection.logs.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No logs yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(connection.logs) { log in
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
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(log.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                    .onChange(of: connection.logs.count) {
                        if let lastLog = connection.logs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
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
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
