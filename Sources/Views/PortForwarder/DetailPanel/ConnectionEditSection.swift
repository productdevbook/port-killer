import SwiftUI

struct ConnectionEditSection: View {
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
    @State private var useDirectExec: Bool = true

    // Kubernetes discovery
    @State private var namespaces: [KubernetesNamespace] = []
    @State private var services: [KubernetesService] = []
    @State private var isLoadingNamespaces = false
    @State private var isLoadingServices = false
    @State private var showNamespacePicker = false
    @State private var showServicePicker = false

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                VStack(spacing: 16) {
                    ConnectionInfoSection(
                        name: $name,
                        namespace: $namespace,
                        service: $service,
                        remotePort: $remotePort,
                        namespaces: namespaces,
                        services: services,
                        isLoadingNamespaces: isLoadingNamespaces,
                        isLoadingServices: isLoadingServices,
                        showNamespacePicker: $showNamespacePicker,
                        showServicePicker: $showServicePicker,
                        onLoadNamespaces: loadNamespaces,
                        onLoadServices: loadServices
                    )

                    Divider()

                    PortMappingSection(
                        localPort: $localPort,
                        remotePort: $remotePort,
                        proxyPort: $proxyPort,
                        proxyEnabled: proxyEnabled
                    )

                    Divider()

                    OptionsSection(
                        proxyEnabled: $proxyEnabled,
                        useDirectExec: $useDirectExec,
                        autoReconnect: $autoReconnect,
                        isEnabled: $isEnabled
                    )
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onAppear {
            loadFromConnection()
            loadNamespaces()
            if !connection.config.namespace.isEmpty {
                loadServices(for: connection.config.namespace)
            }
        }
        .onChange(of: connection.id) { loadFromConnection() }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && namespaces.isEmpty {
                loadNamespaces()
            }
        }
        .onChange(of: name) { saveToConnection() }
        .onChange(of: namespace) { saveToConnection() }
        .onChange(of: service) { saveToConnection() }
        .onChange(of: localPort) { saveToConnection() }
        .onChange(of: remotePort) { saveToConnection() }
        .onChange(of: proxyPort) { saveToConnection() }
        .onChange(of: proxyEnabled) { saveToConnection() }
        .onChange(of: autoReconnect) { saveToConnection() }
        .onChange(of: isEnabled) { saveToConnection() }
        .onChange(of: useDirectExec) { saveToConnection() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Configuration")
                        .font(.headline)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1), in: Capsule())
    }

    // MARK: - Kubernetes Loading

    private func loadNamespaces() {
        isLoadingNamespaces = true
        Task {
            do {
                let result = try await appState.portForwardManager.processManager.fetchNamespaces()
                await MainActor.run {
                    namespaces = result
                    isLoadingNamespaces = false
                }
            } catch {
                await MainActor.run {
                    isLoadingNamespaces = false
                }
            }
        }
    }

    private func loadServices(for ns: String) {
        isLoadingServices = true
        services = []
        Task {
            do {
                let result = try await appState.portForwardManager.processManager.fetchServices(namespace: ns)
                await MainActor.run {
                    services = result
                    isLoadingServices = false
                }
            } catch {
                await MainActor.run {
                    isLoadingServices = false
                }
            }
        }
    }

    // MARK: - Status

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

    // MARK: - Persistence

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
        useDirectExec = connection.config.useDirectExec
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
            useDirectExec: useDirectExec
        )
        appState.portForwardManager.updateConnection(newConfig)
    }
}
