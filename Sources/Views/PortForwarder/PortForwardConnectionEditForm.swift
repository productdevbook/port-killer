import SwiftUI

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
