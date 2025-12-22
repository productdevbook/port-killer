import Foundation

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

    private let scanner: RustPortScanner

    init(scanner: RustPortScanner) {
        self.scanner = scanner
    }

    // MARK: - Actions

    func loadNamespaces() {
        namespaceState = .loading
        namespaces = []
        services = []
        selectedNamespace = nil
        selectedService = nil
        selectedPort = nil

        // Run kubectl on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [scanner, weak self] in
            do {
                let result = try scanner.fetchNamespaces()
                DispatchQueue.main.async {
                    self?.namespaces = result
                    self?.namespaceState = .loaded
                }
            } catch {
                DispatchQueue.main.async {
                    self?.namespaceState = .error(error.localizedDescription)
                }
            }
        }
    }

    func selectNamespace(_ namespace: KubernetesNamespace) {
        selectedNamespace = namespace
        selectedService = nil
        selectedPort = nil
        services = []
        serviceState = .loading

        let namespaceName = namespace.name

        // Run kubectl on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [scanner, weak self] in
            do {
                let result = try scanner.fetchServices(namespace: namespaceName)
                DispatchQueue.main.async {
                    self?.services = result
                    self?.serviceState = .loaded
                }
            } catch {
                DispatchQueue.main.async {
                    self?.serviceState = .error(error.localizedDescription)
                }
            }
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
}
