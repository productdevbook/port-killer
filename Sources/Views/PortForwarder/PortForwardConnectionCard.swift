import SwiftUI

struct PortForwardConnectionCard: View {
    let connection: PortForwardConnectionState
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        } else {
            return .gray.opacity(0.4)
        }
    }

    private var statusText: String {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return "Error"
        } else if connection.isFullyConnected {
            return "Connected"
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return "Connecting..."
        } else {
            return "Disconnected"
        }
    }

    private var isConnecting: Bool {
        connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting
    }

    @ViewBuilder
    private var inlineActionButton: some View {
        if isConnecting {
            Button {
                appState.portForwardManager.stopConnection(connection.id)
            } label: {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        } else if connection.isFullyConnected {
            Button {
                appState.portForwardManager.stopConnection(connection.id)
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Stop")
        } else {
            Button {
                appState.portForwardManager.startConnection(connection.id)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Start")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(connection.config.name)
                    .fontWeight(.medium)

                Text("\u{00B7}")
                    .foregroundStyle(.tertiary)

                Text("\(connection.config.namespace)/\(connection.config.service)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                // Port info
                Text(":" + String(connection.effectivePort))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Status badge
                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())

                // Inline action button
                inlineActionButton

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    appState.portForwardManager.removeConnection(connection.id)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                PortForwardConnectionEditForm(connection: connection)
                    .padding(12)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : statusColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : statusColor.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
}

// MARK: - Edit Form

struct PortForwardConnectionEditForm: View {
    let connection: PortForwardConnectionState
    @Environment(AppState.self) private var appState

    @State private var name: String
    @State private var namespace: String
    @State private var service: String
    @State private var localPort: Int
    @State private var remotePort: Int
    @State private var proxyEnabled: Bool
    @State private var proxyPort: Int
    @State private var isEnabled: Bool
    @State private var autoReconnect: Bool
    @State private var useDirectExec: Bool

    init(connection: PortForwardConnectionState) {
        self.connection = connection
        _name = State(initialValue: connection.config.name)
        _namespace = State(initialValue: connection.config.namespace)
        _service = State(initialValue: connection.config.service)
        _localPort = State(initialValue: connection.config.localPort)
        _remotePort = State(initialValue: connection.config.remotePort)
        _proxyEnabled = State(initialValue: connection.config.proxyPort != nil)
        _proxyPort = State(initialValue: connection.config.proxyPort ?? connection.config.localPort - 1)
        _isEnabled = State(initialValue: connection.config.isEnabled)
        _autoReconnect = State(initialValue: connection.config.autoReconnect)
        _useDirectExec = State(initialValue: connection.config.useDirectExec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error message and Restart button
            HStack(spacing: 12) {
                if let error = connection.lastError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    appState.portForwardManager.restartConnection(connection.id)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(connection.portForwardStatus == .disconnected)
            }

            Divider()

            // Edit form
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onChange(of: name) { save() }
                }

                GridRow {
                    Text("Namespace").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $namespace)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onChange(of: namespace) { save() }
                }

                GridRow {
                    Text("Service").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    TextField("", text: $service)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onChange(of: service) { save() }
                }

                GridRow {
                    Text("Ports").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    HStack(spacing: 8) {
                        TextField("", value: $localPort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onChange(of: localPort) { save() }
                        Text("\u{2192}").foregroundStyle(.tertiary)
                        TextField("", value: $remotePort, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .onChange(of: remotePort) { save() }
                    }
                }

                GridRow {
                    Text("Proxy").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    HStack(spacing: 12) {
                        Toggle("", isOn: $proxyEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: proxyEnabled) { save() }

                        if proxyEnabled {
                            TextField("", value: $proxyPort, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                                .onChange(of: proxyPort) { save() }

                            Toggle("Multi-conn", isOn: $useDirectExec)
                                .toggleStyle(.checkbox)
                                .onChange(of: useDirectExec) { save() }
                                .help("Multiple simultaneous connections")
                        }
                    }
                }

                GridRow {
                    Text("Options").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    HStack(spacing: 16) {
                        Toggle("Enabled", isOn: $isEnabled)
                            .onChange(of: isEnabled) { save() }
                        Toggle("Auto Reconnect", isOn: $autoReconnect)
                            .onChange(of: autoReconnect) { save() }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func save() {
        var config = connection.config
        config.name = name
        config.namespace = namespace
        config.service = service
        config.localPort = localPort
        config.remotePort = remotePort
        config.proxyPort = proxyEnabled ? proxyPort : nil
        config.isEnabled = isEnabled
        config.autoReconnect = autoReconnect
        config.useDirectExec = useDirectExec
        appState.portForwardManager.updateConnection(config)
    }
}
