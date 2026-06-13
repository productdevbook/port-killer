import Foundation

extension PortForwardProcessManager {
    /// Fetches all Kubernetes namespaces.
    func fetchNamespaces() async throws -> [KubernetesNamespace] {
        let output = try await executeKubectl(arguments: ["get", "namespaces", "-o", "json"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesNamespace.ListResponse.self,
                from: Data(output.utf8)
            )
            let namespaces = KubernetesNamespace.from(response: response)
            return namespaces.sorted { $0.name < $1.name }
        } catch {
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    /// Fetches services in a specific namespace.
    func fetchServices(namespace: String) async throws -> [KubernetesService] {
        let output = try await executeKubectl(arguments: ["get", "services", "-n", namespace, "-o", "json"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesService.ListResponse.self,
                from: Data(output.utf8)
            )
            let services = KubernetesService.from(response: response)
            return services.sorted { $0.name < $1.name }
        } catch {
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    /// Executes a kubectl command and returns the output.
    nonisolated func executeKubectl(arguments: [String]) async throws -> String {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        guard let result = await ProcessExecutor.run(kubectlPath, arguments: arguments) else {
            throw KubectlError.kubectlNotFound
        }

        guard result.succeeded else {
            let errorOutput = result.standardError
            if errorOutput.contains("Unable to connect") ||
               errorOutput.contains("connection refused") ||
               errorOutput.contains("no configuration") ||
               errorOutput.contains("dial tcp") {
                throw KubectlError.clusterNotConnected
            }
            throw KubectlError.executionFailed(
                errorOutput.isEmpty ? "Unknown error" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.standardOutput
    }
}
