public import Foundation

public struct KubernetesService: Identifiable, Hashable, Sendable {
    public struct Port: Identifiable, Hashable, Sendable {
        public var name: String?
        public var port: Int

        public var id: Int { port }

        public var title: String {
            guard let name, !name.isEmpty else { return String(port) }
            return "\(port) (\(name))"
        }
    }

    public var name: String
    public var namespace: String
    public var type: String
    public var ports: [Port]

    public var id: String { "\(namespace)/\(name)" }
}

public enum KubectlError: Error, LocalizedError, Sendable, Equatable {
    case notInstalled
    case clusterUnreachable(String)
    case failed(String)
    case unreadableResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: "kubectl isn't installed. Install it with \(CommandLineTool.kubectl.installCommand)."
        case .clusterUnreachable(let message): "Can't reach the Kubernetes cluster. \(message)"
        case .failed(let message): "kubectl failed: \(message)"
        case .unreadableResponse(let message): "Couldn't read kubectl's response: \(message)"
        }
    }

    static func classify(_ output: String) -> KubectlError {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let unreachable = ["Unable to connect", "connection refused", "no configuration", "dial tcp", "couldn't get current server API group list"]
        if unreachable.contains(where: text.contains) {
            return .clusterUnreachable(text)
        }
        return .failed(text.isEmpty ? "Unknown error" : text)
    }
}

public struct Kubectl: Sendable {
    public var executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public func currentContext() async -> String? {
        guard let result = try? await run(["config", "current-context"]), result.succeeded else { return nil }
        let context = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return context.isEmpty ? nil : context
    }

    @concurrent
    public func namespaces() async throws(KubectlError) -> [String] {
        let data = try await json(["get", "namespaces", "-o", "json"])
        do {
            return try Self.parseNamespaces(data)
        } catch {
            throw .unreadableResponse(error.localizedDescription)
        }
    }

    @concurrent
    public func services(namespace: String) async throws(KubectlError) -> [KubernetesService] {
        let data = try await json(["get", "services", "-n", namespace, "-o", "json"])
        do {
            return try Self.parseServices(data)
        } catch {
            throw .unreadableResponse(error.localizedDescription)
        }
    }

    private func json(_ arguments: [String]) async throws(KubectlError) -> Data {
        let result: CommandResult
        do {
            result = try await run(arguments)
        } catch {
            throw .failed(error.localizedDescription)
        }
        guard result.succeeded else { throw KubectlError.classify(result.error.isEmpty ? result.output : result.error) }
        return Data(result.output.utf8)
    }

    private func run(_ arguments: [String]) async throws -> CommandResult {
        try await CommandRunner.run(executable, arguments)
    }

    static func parseNamespaces(_ data: Data) throws -> [String] {
        struct List: Decodable {
            struct Item: Decodable {
                struct Metadata: Decodable { var name: String }
                var metadata: Metadata
            }
            var items: [Item]
        }
        return try JSONDecoder().decode(List.self, from: data).items.map(\.metadata.name).sorted()
    }

    static func parseServices(_ data: Data) throws -> [KubernetesService] {
        struct List: Decodable {
            struct Item: Decodable {
                struct Metadata: Decodable {
                    var name: String
                    var namespace: String
                }
                struct Spec: Decodable {
                    struct Port: Decodable {
                        var name: String?
                        var port: Int
                    }
                    var type: String?
                    var ports: [Port]?
                }
                var metadata: Metadata
                var spec: Spec
            }
            var items: [Item]
        }
        return try JSONDecoder().decode(List.self, from: data).items.map { item in
            KubernetesService(
                name: item.metadata.name,
                namespace: item.metadata.namespace,
                type: item.spec.type ?? "ClusterIP",
                ports: (item.spec.ports ?? []).map { KubernetesService.Port(name: $0.name, port: $0.port) }
            )
        }
        .sorted { $0.name < $1.name }
    }
}
