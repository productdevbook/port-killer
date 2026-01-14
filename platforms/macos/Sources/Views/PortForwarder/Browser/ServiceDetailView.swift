import SwiftUI

struct ServiceDetailView: View {
    let service: KubernetesService
    let selectedPort: KubernetesService.ServicePort?
    @Binding var proxyEnabled: Bool
    let suggestedLocalPort: Int
    let onPortSelect: (KubernetesService.ServicePort) -> Void

    private var suggestedProxyPort: Int {
        suggestedLocalPort - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Service Details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Service Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.name)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Text(service.type)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            if let ip = service.clusterIP, ip != "None" {
                                Text(ip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Port Selection
                    Text("Select Port")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if service.ports.isEmpty {
                        Text("No ports defined")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(service.ports) { port in
                            PortSelectionRow(
                                port: port,
                                isSelected: selectedPort?.id == port.id,
                                onSelect: { onPortSelect(port) }
                            )
                        }
                    }

                    // Port Configuration
                    if selectedPort != nil {
                        Divider()

                        Text("Port Configuration")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Local port:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(suggestedLocalPort))
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                            }

                            Toggle("Enable Proxy (socat)", isOn: $proxyEnabled)
                                .toggleStyle(.checkbox)

                            if proxyEnabled {
                                HStack {
                                    Text("Proxy port:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(String(suggestedProxyPort))
                                        .font(.system(.caption, design: .monospaced, weight: .medium))
                                }
                            }

                            Divider()

                            HStack {
                                Text("Connect to:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("localhost:" + String(proxyEnabled ? suggestedProxyPort : suggestedLocalPort))
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    Spacer()
                }
                .padding(10)
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

struct PortSelectionRow: View {
    let port: KubernetesService.ServicePort
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(String(port.port))
                            .font(.system(.body, design: .monospaced, weight: .medium))
                        if let name = port.name, !name.isEmpty {
                            Text("(\(name))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let proto = port.protocol {
                        Text(proto)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }
            .padding(8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
