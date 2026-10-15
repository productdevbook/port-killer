import Foundation

extension PortForwardProcessManager {
    /// Fetches the context names available in the (optionally custom) kubeconfig.
    func fetchContexts(target: KubectlTarget = .default) async throws -> [String] {
        let output = try await executeKubectl(
            arguments: target.kubeconfigOnly.arguments(["config", "get-contexts", "-o", "name"])
        )
        return KubernetesContextParser.parseContextNames(output)
    }

    /// Returns the kubeconfig's current context, or `nil` if none is set.
    func fetchCurrentContext(target: KubectlTarget = .default) async -> String? {
        guard let output = try? await executeKubectl(
            arguments: target.kubeconfigOnly.arguments(["config", "current-context"])
        ) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Fetches all Kubernetes namespaces.
    func fetchNamespaces(target: KubectlTarget = .default) async throws -> [KubernetesNamespace] {
        let output = try await executeKubectl(arguments: target.arguments(["get", "namespaces", "-o", "json"]))

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
    func fetchServices(namespace: String, target: KubectlTarget = .default) async throws -> [KubernetesService] {
        let output = try await executeKubectl(
            arguments: target.arguments(["get", "services", "-n", namespace, "-o", "json"])
        )

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
