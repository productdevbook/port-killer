import SwiftUI

struct ConnectionInfoSection: View {
    @Binding var name: String
    @Binding var namespace: String
    @Binding var service: String
    @Binding var remotePort: String

    let namespaces: [KubernetesNamespace]
    let services: [KubernetesService]
    let isLoadingNamespaces: Bool
    let isLoadingServices: Bool
    @Binding var showNamespacePicker: Bool
    @Binding var showServicePicker: Bool

    let onLoadNamespaces: () -> Void
    let onLoadServices: (String) -> Void

    var body: some View {
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
                                onLoadServices(selected)
                                showNamespacePicker = false
                            },
                            onRefresh: { onLoadNamespaces() }
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
                            onRefresh: { onLoadServices(namespace) }
                        )
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }
}
