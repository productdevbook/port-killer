import SwiftUI

struct ServiceBrowserTab: View {
    @Environment(AppState.self) private var appState
    @State private var isBrowsing = false

    var body: some View {
        VStack {
            if isBrowsing {
                ServiceBrowserEmbedded(
                    discoveryManager: appState.kubernetesDiscoveryManager,
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
                        Task {
                            appState.kubernetesDiscoveryManager.loadNamespaces()
                        }
                        isBrowsing = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!appState.scanner.isKubectlAvailable())

                    if !appState.scanner.isKubectlAvailable() {
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

struct ServiceBrowserEmbedded: View {
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
                        Task { discoveryManager.selectNamespace(namespace) }
                    },
                    onRefresh: {
                        Task { discoveryManager.loadNamespaces() }
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
