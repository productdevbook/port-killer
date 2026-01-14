import Foundation
import Defaults

// MARK: - Discovery State

enum KubernetesDiscoveryState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Kubernetes Discovery Manager

@Observable
@MainActor
final class KubernetesDiscoveryManager: Identifiable {
    let id = UUID()

    var namespaces: [KubernetesNamespace] = []
    var services: [KubernetesService] = []
    var selectedNamespace: KubernetesNamespace?
    var selectedService: KubernetesService?
    var selectedPort: KubernetesService.ServicePort?
    var proxyEnabled = true

    var namespaceState: KubernetesDiscoveryState = .idle
    var serviceState: KubernetesDiscoveryState = .idle

    private let processManager: PortForwardProcessManager

    init(processManager: PortForwardProcessManager) {
        self.processManager = processManager
    }

    // MARK: - Actions

    func loadNamespaces() async {
        namespaceState = .loading
        namespaces = []
        services = []
        selectedNamespace = nil
        selectedService = nil
        selectedPort = nil

        do {
            let fetchedNamespaces = try await processManager.fetchNamespaces()
            // Merge with custom namespaces
            let customNamespaceNames = Defaults[.customNamespaces]
            let customNamespaces = customNamespaceNames.map { KubernetesNamespace(name: $0, isCustom: true) }

            // Combine and remove duplicates (prefer auto-fetched over custom)
            var combinedNamespaces = fetchedNamespaces
            for customNS in customNamespaces {
                if !combinedNamespaces.contains(where: { $0.name == customNS.name }) {
                    combinedNamespaces.append(customNS)
                }
            }

            namespaces = combinedNamespaces.sorted { $0.name < $1.name }
            namespaceState = .loaded
        } catch {
            // On error, fall back to custom namespaces only
            let customNamespaceNames = Defaults[.customNamespaces]
            if !customNamespaceNames.isEmpty {
                namespaces = customNamespaceNames.map { KubernetesNamespace(name: $0, isCustom: true) }
                    .sorted { $0.name < $1.name }
                namespaceState = .loaded
            } else {
                let message = (error as? KubectlError)?.errorDescription ?? error.localizedDescription
                namespaceState = .error(message)
            }
        }
    }

    func selectNamespace(_ namespace: KubernetesNamespace) async {
        selectedNamespace = namespace
        selectedService = nil
        selectedPort = nil
        services = []
        serviceState = .loading

        do {
            services = try await processManager.fetchServices(namespace: namespace.name)
            serviceState = .loaded
        } catch {
            let message = (error as? KubectlError)?.errorDescription ?? error.localizedDescription
            serviceState = .error(message)
        }
    }

    func selectService(_ service: KubernetesService) {
        selectedService = service
        selectedPort = service.ports.first
    }

    func selectPort(_ port: KubernetesService.ServicePort) {
        selectedPort = port
    }

    // MARK: - Connection Creation

    func createConnectionConfig() -> PortForwardConnectionConfig? {
        guard let namespace = selectedNamespace,
              let service = selectedService,
              let port = selectedPort else {
            return nil
        }

        let remotePort = port.port
        let localPort = suggestLocalPort(for: remotePort)
        let proxyPort = proxyEnabled ? suggestProxyPort(for: localPort) : nil

        return PortForwardConnectionConfig(
            name: service.name,
            namespace: namespace.name,
            service: service.name,
            localPort: localPort,
            remotePort: remotePort,
            proxyPort: proxyPort
        )
    }

    func suggestLocalPort(for remotePort: Int) -> Int {
        switch remotePort {
        case 80: return 8080
        case 443: return 8443
        default:
            return remotePort > 1024 ? remotePort : remotePort + 8000
        }
    }

    func suggestProxyPort(for localPort: Int) -> Int {
        return localPort - 1
    }

    func reset() {
        namespaces = []
        services = []
        selectedNamespace = nil
        selectedService = nil
        selectedPort = nil
        namespaceState = .idle
        serviceState = .idle
    }

    // MARK: - Custom Namespace Management

    func addCustomNamespace(_ namespaceName: String) {
        let trimmedName = namespaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var customNamespaces = Defaults[.customNamespaces]
        if !customNamespaces.contains(trimmedName) {
            customNamespaces.append(trimmedName)
            Defaults[.customNamespaces] = customNamespaces

            // Add to current namespace list if not already present
            if !namespaces.contains(where: { $0.name == trimmedName }) {
                let newNamespace = KubernetesNamespace(name: trimmedName, isCustom: true)
                namespaces.append(newNamespace)
                namespaces.sort { $0.name < $1.name }

                // Update state to loaded if it was in error
                if case .error = namespaceState {
                    namespaceState = .loaded
                }
            }
        }
    }

    func addCustomNamespaces(_ namespaceNames: [String]) {
        for name in namespaceNames {
            addCustomNamespace(name)
        }
    }

    func removeCustomNamespace(_ namespace: KubernetesNamespace) {
        guard namespace.isCustom else { return }

        var customNamespaces = Defaults[.customNamespaces]
        customNamespaces.removeAll { $0 == namespace.name }
        Defaults[.customNamespaces] = customNamespaces

        // Remove from current namespace list
        namespaces.removeAll { $0.name == namespace.name }

        // If no namespaces left, reset to idle state
        if namespaces.isEmpty {
            namespaceState = .idle
        }
    }
}
