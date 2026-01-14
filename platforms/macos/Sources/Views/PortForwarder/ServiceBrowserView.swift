import SwiftUI

struct ServiceBrowserView: View {
    @Bindable var discoveryManager: KubernetesDiscoveryManager
    let onServiceSelected: (PortForwardConnectionConfig) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Import from Kubernetes")
                    .font(.headline)
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content - 3 panel layout
            HStack(spacing: 0) {
                // Namespace List (left panel)
                NamespaceListView(
                    namespaces: discoveryManager.namespaces,
                    selectedNamespace: discoveryManager.selectedNamespace,
                    state: discoveryManager.namespaceState,
                    onSelect: { namespace in
                        Task { await discoveryManager.selectNamespace(namespace) }
                    },
                    onRefresh: {
                        Task { await discoveryManager.loadNamespaces() }
                    },
                    onAddCustom: { namespaceNames in
                        discoveryManager.addCustomNamespaces(namespaceNames)
                    },
                    onRemoveCustom: { namespace in
                        discoveryManager.removeCustomNamespace(namespace)
                    }
                )
                .frame(width: 180)

                Divider()

                // Service List (middle panel)
                ServiceListView(
                    services: discoveryManager.services,
                    selectedService: discoveryManager.selectedService,
                    state: discoveryManager.serviceState,
                    onSelect: { service in
                        discoveryManager.selectService(service)
                    }
                )
                .frame(minWidth: 180)

                Divider()

                // Port Selection (right panel)
                if let service = discoveryManager.selectedService {
                    ServiceDetailView(
                        service: service,
                        selectedPort: discoveryManager.selectedPort,
                        proxyEnabled: $discoveryManager.proxyEnabled,
                        suggestedLocalPort: discoveryManager.suggestLocalPort(for: discoveryManager.selectedPort?.port ?? 0),
                        onPortSelect: { port in
                            discoveryManager.selectPort(port)
                        }
                    )
                    .frame(width: 200)
                } else {
                    EmptySelectionView()
                        .frame(width: 200)
                }
            }

            Divider()

            // Footer with action buttons
            HStack {
                if case .error(let message) = discoveryManager.namespaceState {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    if let config = discoveryManager.createConnectionConfig() {
                        onServiceSelected(config)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(discoveryManager.selectedPort == nil)
            }
            .padding()
        }
        .frame(width: 800, height: 500)
        .task {
            if discoveryManager.namespaceState == .idle {
                await discoveryManager.loadNamespaces()
            }
        }
    }
}
