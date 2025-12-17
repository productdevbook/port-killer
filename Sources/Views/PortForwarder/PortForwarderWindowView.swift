import SwiftUI
import Defaults

struct PortForwarderWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        TabView {
            ConnectionsTab(discoveryManager: $discoveryManager)
                .tabItem {
                    Label("Connections", systemImage: "point.3.connected.trianglepath.dotted")
                }

            ServiceBrowserTab()
                .tabItem {
                    Label("Browse", systemImage: "magnifyingglass")
                }

            PortForwarderSettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .frame(width: 900, height: 650)
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

// MARK: - Connections Tab

private struct ConnectionsTab: View {
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
                .frame(minWidth: 300)
        }
    }
}

// MARK: - Service Browser Tab

private struct ServiceBrowserTab: View {
    @Environment(AppState.self) private var appState
    @State private var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        VStack {
            if let dm = discoveryManager {
                ServiceBrowserEmbedded(
                    discoveryManager: dm,
                    onServiceSelected: { config in
                        appState.portForwardManager.addConnection(config)
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text("Kubernetes Service Browser")
                        .font(.title2)

                    Text("Browse your Kubernetes cluster to find services and create port-forward connections.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button("Start Browsing") {
                        let dm = KubernetesDiscoveryManager(processManager: appState.portForwardManager.processManager)
                        Task { await dm.loadNamespaces() }
                        discoveryManager = dm
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!DependencyChecker.shared.allRequiredInstalled)

                    if !DependencyChecker.shared.allRequiredInstalled {
                        Text("kubectl is required")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct ServiceBrowserEmbedded: View {
    @Bindable var discoveryManager: KubernetesDiscoveryManager
    let onServiceSelected: (PortForwardConnectionConfig) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 3 panel layout
            HStack(spacing: 0) {
                // Namespace List
                NamespacePanel(
                    namespaces: discoveryManager.namespaces,
                    selectedNamespace: discoveryManager.selectedNamespace,
                    state: discoveryManager.namespaceState,
                    onSelect: { namespace in
                        Task { await discoveryManager.selectNamespace(namespace) }
                    },
                    onRefresh: {
                        Task { await discoveryManager.loadNamespaces() }
                    }
                )
                .frame(width: 200)

                Divider()

                // Service List
                ServicePanel(
                    services: discoveryManager.services,
                    selectedService: discoveryManager.selectedService,
                    state: discoveryManager.serviceState,
                    onSelect: { service in
                        discoveryManager.selectService(service)
                    }
                )
                .frame(minWidth: 250)

                Divider()

                // Port Selection
                PortPanel(
                    service: discoveryManager.selectedService,
                    selectedPort: discoveryManager.selectedPort,
                    proxyEnabled: $discoveryManager.proxyEnabled,
                    discoveryManager: discoveryManager,
                    onPortSelect: { port in
                        discoveryManager.selectPort(port)
                    },
                    onAdd: {
                        if let config = discoveryManager.createConnectionConfig() {
                            onServiceSelected(config)
                        }
                    }
                )
                .frame(width: 250)
            }
        }
    }
}

private struct NamespacePanel: View {
    let namespaces: [KubernetesNamespace]
    let selectedNamespace: KubernetesNamespace?
    let state: KubernetesDiscoveryState
    let onSelect: (KubernetesNamespace) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Namespaces")
                    .font(.headline)
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(state == .loading)
            }
            .padding(12)

            Divider()

            if state == .loading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if case .error(let msg) = state {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry", action: onRefresh)
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .padding()
            } else {
                List(namespaces, selection: .constant(selectedNamespace?.id)) { ns in
                    Text(ns.name)
                        .font(.system(.body, design: .monospaced))
                        .tag(ns.id)
                        .onTapGesture { onSelect(ns) }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ServicePanel: View {
    let services: [KubernetesService]
    let selectedService: KubernetesService?
    let state: KubernetesDiscoveryState
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Services")
                    .font(.headline)
                Spacer()
                Text("\(services.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if state == .loading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if state == .idle {
                VStack {
                    Spacer()
                    Text("Select a namespace")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                List(services, selection: .constant(selectedService?.id)) { svc in
                    VStack(alignment: .leading) {
                        Text(svc.name)
                            .font(.system(.body, design: .monospaced))
                        Text("\(svc.type) \u{00B7} \(svc.ports.count) ports")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(svc.id)
                    .onTapGesture { onSelect(svc) }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct PortPanel: View {
    let service: KubernetesService?
    let selectedPort: KubernetesService.ServicePort?
    @Binding var proxyEnabled: Bool
    let discoveryManager: KubernetesDiscoveryManager
    let onPortSelect: (KubernetesService.ServicePort) -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Port Configuration")
                    .font(.headline)
                Spacer()
            }
            .padding(12)

            Divider()

            if let service = service {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Port selection
                        ForEach(service.ports) { port in
                            Button {
                                onPortSelect(port)
                            } label: {
                                HStack {
                                    Image(systemName: selectedPort?.id == port.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedPort?.id == port.id ? .blue : .secondary)
                                    Text(port.displayName)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        if selectedPort != nil {
                            Divider()

                            Toggle("Enable Proxy (socat)", isOn: $proxyEnabled)

                            let localPort = discoveryManager.suggestLocalPort(for: selectedPort?.port ?? 0)
                            let proxyPort = discoveryManager.suggestProxyPort(for: localPort)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local: \(localPort)")
                                    .font(.caption)
                                if proxyEnabled {
                                    Text("Proxy: \(proxyPort)")
                                        .font(.caption)
                                }
                                Text("Connect to: localhost:\(proxyEnabled ? proxyPort : localPort)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }

                            Button("Add Connection", action: onAdd)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a service")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Settings Tab

struct PortForwarderSettingsTab: View {
    @AppStorage("portForwardAutoStart") private var autoStart = false
    @AppStorage("portForwardShowNotifications") private var showNotifications = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Auto-start connections on app launch", isOn: $autoStart)
            }

            Section("Notifications") {
                Toggle("Show connection notifications", isOn: $showNotifications)
            }

            Section("Dependencies") {
                LabeledContent("kubectl") {
                    DependencyStatusView(dependency: DependencyChecker.shared.kubectl)
                }

                LabeledContent("socat") {
                    DependencyStatusView(dependency: DependencyChecker.shared.socat)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct DependencyStatusView: View {
    let dependency: PortForwardDependency
    @State private var isInstalling = false

    var body: some View {
        HStack(spacing: 6) {
            if dependency.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Installed")
                    .foregroundStyle(.secondary)
            } else {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Install") {
                        install()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !dependency.isRequired {
                    Text("(optional)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func install() {
        isInstalling = true
        Task {
            _ = await DependencyChecker.shared.checkAndInstallMissing()
            await MainActor.run { isInstalling = false }
        }
    }
}
