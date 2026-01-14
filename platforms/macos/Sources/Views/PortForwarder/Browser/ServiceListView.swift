import SwiftUI

struct ServiceListView: View {
    let services: [KubernetesService]
    let selectedService: KubernetesService?
    let state: KubernetesDiscoveryState
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !services.isEmpty {
                    Text("\(services.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            Group {
                switch state {
                case .loading:
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading services...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                case .error(let message):
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                        Spacer()
                    }

                case .idle:
                    VStack {
                        Spacer()
                        Image(systemName: "arrow.left")
                            .foregroundStyle(.tertiary)
                        Text("Select a namespace")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }

                case .loaded:
                    if services.isEmpty {
                        VStack {
                            Spacer()
                            Text("No services found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(services) { service in
                                    ServiceRow(
                                        service: service,
                                        isSelected: selectedService?.id == service.id,
                                        onSelect: onSelect
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.02))
    }
}

struct ServiceRow: View {
    let service: KubernetesService
    let isSelected: Bool
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        Button {
            onSelect(service)
        } label: {
            HStack {
                Image(systemName: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(service.type)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                        Text("\(service.ports.count) port\(service.ports.count != 1 ? "s" : "")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
