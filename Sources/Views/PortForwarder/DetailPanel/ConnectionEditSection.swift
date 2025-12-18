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
    @State private var namespaceSearch = ""
    @State private var serviceSearch = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            if isExpanded {
                VStack(spacing: 16) {
                    // Connection info section
                    connectionInfoSection

                    Divider()

                    // Port mapping section
                    portMappingSection

                    Divider()

                    // Options section
                    optionsSection
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

    // MARK: - Connection Info Section

    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connection", systemImage: "link")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 22, alignment: .center)
                    TextField("Connection name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 22, alignment: .center)

                    // Namespace picker
                    Button {
                        showNamespacePicker.toggle()
                    } label: {
                        HStack {
                            Text(namespace.isEmpty ? "namespace" : namespace)
                                .foregroundStyle(namespace.isEmpty ? .tertiary : .primary)
                            Spacer()
                            if isLoadingNamespaces {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 140)
                    .popover(isPresented: $showNamespacePicker, arrowEdge: .bottom) {
                        SearchablePickerView(
                            items: namespaces.map(\.name),
                            selection: namespace,
                            isLoading: isLoadingNamespaces,
                            placeholder: "Search namespaces...",
                            onSelect: { selected in
                                namespace = selected
                                loadServices(for: selected)
                                showNamespacePicker = false
                            },
                            onRefresh: { loadNamespaces() }
                        )
                    }

                    Image(systemName: "server.rack")
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 22, alignment: .center)

                    // Service picker
                    Button {
                        showServicePicker.toggle()
                    } label: {
                        HStack {
                            Text(service.isEmpty ? "service" : service)
                                .foregroundStyle(service.isEmpty ? .tertiary : .primary)
                            Spacer()
                            if isLoadingServices {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showServicePicker, arrowEdge: .bottom) {
                        SearchablePickerView(
                            items: services.map(\.name),
                            selection: service,
                            isLoading: isLoadingServices,
                            placeholder: "Search services...",
                            onSelect: { selected in
                                service = selected
                                // Auto-fill remote port
                                if let svc = services.first(where: { $0.name == selected }),
                                   let firstPort = svc.ports.first {
                                    remotePort = String(firstPort.port)
                                }
                                showServicePicker = false
                            },
                            onRefresh: { loadServices(for: namespace) }
                        )
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
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

    // MARK: - Port Mapping Section

    private var portMappingSection: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Port Mapping", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Port flow visualization - centered
            HStack(alignment: .bottom, spacing: 8) {
                // Proxy port (if enabled)
                if proxyEnabled {
                    VStack(spacing: 4) {
                        Text("Proxy")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("port", text: $proxyPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.center)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .frame(height: 22)
                }

                // Local port
                VStack(spacing: 4) {
                    Text("Local")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("port", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.center)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.blue)
                    .frame(height: 22)

                // Kubernetes icon
                Image(systemName: "cloud")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .frame(height: 22)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.blue)
                    .frame(height: 22)

                // Remote port
                VStack(spacing: 4) {
                    Text("Remote")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("port", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.center)
                }
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Options Section

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Options", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Toggle(isOn: $proxyEnabled) {
                    Label("Proxy", systemImage: "network")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if proxyEnabled {
                    Toggle(isOn: $useDirectExec) {
                        Label("Multi-conn", systemImage: "arrow.triangle.branch")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Enable multiple simultaneous connections")
                }

                Spacer()
            }

            HStack(spacing: 20) {
                Toggle(isOn: $autoReconnect) {
                    Label("Auto Reconnect", systemImage: "arrow.clockwise")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $isEnabled) {
                    Label("Enabled", systemImage: "power")
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .font(.callout)
        }
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

// MARK: - Searchable Picker View

private struct SearchablePickerView: View {
    let items: [String]
    let selection: String
    let isLoading: Bool
    let placeholder: String
    let onSelect: (String) -> Void
    let onRefresh: () -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [String] {
        if searchText.isEmpty {
            return items
        }
        return items.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
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
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // List
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            } else if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    if items.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                        Button("Refresh") { onRefresh() }
                            .buttonStyle(.bordered)
                    } else {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems, id: \.self) { item in
                            Button {
                                onSelect(item)
                            } label: {
                                HStack {
                                    if item == selection {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                            .frame(width: 16)
                                    } else {
                                        Color.clear.frame(width: 16)
                                    }
                                    Text(item)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(item == selection ? Color.accentColor.opacity(0.1) : Color.clear)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Refresh button
            Button {
                onRefresh()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 220)
        .onAppear {
            isSearchFocused = true
        }
    }
}
