import Foundation

// MARK: - kubectl Target

/// Identifies which cluster a kubectl invocation talks to: an optional context
/// and an optional kubeconfig file. Empty values fall back to kubectl's defaults
/// (current context, `$KUBECONFIG` / `~/.kube/config`).
nonisolated struct KubectlTarget: Equatable, Hashable, Sendable {
    var context: String?
    var kubeconfigPath: String?

    static let `default` = KubectlTarget()

    init(context: String? = nil, kubeconfigPath: String? = nil) {
        self.context = context
        self.kubeconfigPath = kubeconfigPath
    }

    /// Context name, or `nil` when the current context should be used.
    var resolvedContext: String? {
        guard let trimmed = context?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Absolute kubeconfig path (tilde expanded), or `nil` for kubectl's default.
    var resolvedKubeconfigPath: String? {
        guard let trimmed = kubeconfigPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }

    /// Only the kubeconfig part, used for `kubectl config` queries that list contexts.
    var kubeconfigOnly: KubectlTarget {
        KubectlTarget(kubeconfigPath: kubeconfigPath)
    }

    /// Global kubectl flags selecting this target. Uses the `--flag=value` form so a
    /// value can never be parsed as a separate flag.
    var globalArguments: [String] {
        var args: [String] = []
        if let path = resolvedKubeconfigPath {
            args.append("--kubeconfig=\(path)")
        }
        if let context = resolvedContext {
            args.append("--context=\(context)")
        }
        return args
    }

    /// Prefixes the given kubectl arguments with the target's global flags.
    func arguments(_ arguments: [String]) -> [String] {
        globalArguments + arguments
    }
}

// MARK: - Context List Parsing

nonisolated enum KubernetesContextParser {
    /// Parses the output of `kubectl config get-contexts -o name`.
    static func parseContextNames(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

// MARK: - Namespace

struct KubernetesNamespace: Identifiable, Codable, Sendable, Hashable {
    let name: String
    let isCustom: Bool

    var id: String { name }

    init(name: String, isCustom: Bool = false) {
        self.name = name
        self.isCustom = isCustom
    }
}

// MARK: - Service

struct KubernetesService: Identifiable, Codable, Sendable, Hashable {
    let name: String
    let namespace: String
    let type: String
    let clusterIP: String?
    let ports: [ServicePort]

    var id: String { "\(namespace)/\(name)" }

    struct ServicePort: Codable, Sendable, Hashable, Identifiable {
        let name: String?
        let port: Int
        let targetPort: Int
        let `protocol`: String?

        var id: Int { port }

        var displayName: String {
            if let name = name, !name.isEmpty {
                return "\(String(port)) (\(name))"
            }
            return String(port)
        }
    }
}

// MARK: - kubectl JSON Response Parsing

extension KubernetesNamespace {
    struct ListResponse: Codable {
        let items: [Item]

        struct Item: Codable {
            let metadata: Metadata

            struct Metadata: Codable {
                let name: String
            }
        }
    }

    static func from(response: ListResponse) -> [KubernetesNamespace] {
        response.items.map { KubernetesNamespace(name: $0.metadata.name) }
    }
}

extension KubernetesService {
    struct ListResponse: Codable {
        let items: [Item]

        struct Item: Codable {
            let metadata: Metadata
            let spec: Spec

            struct Metadata: Codable {
                let name: String
                let namespace: String
            }

            struct Spec: Codable {
                let type: String?
                let clusterIP: String?
                let ports: [Port]?

                struct Port: Codable {
                    let name: String?
                    let port: Int
                    let targetPort: TargetPort?
                    let `protocol`: String?

                    // targetPort can be either Int or String in Kubernetes
                    enum TargetPort: Codable {
                        case int(Int)
                        case string(String)

                        init(from decoder: Decoder) throws {
                            let container = try decoder.singleValueContainer()
                            if let intValue = try? container.decode(Int.self) {
                                self = .int(intValue)
                            } else if let stringValue = try? container.decode(String.self) {
                                self = .string(stringValue)
                            } else {
                                throw DecodingError.dataCorruptedError(
                                    in: container,
                                    debugDescription: "Cannot decode targetPort"
                                )
                            }
                        }

                        func encode(to encoder: Encoder) throws {
                            var container = encoder.singleValueContainer()
                            switch self {
                            case .int(let value): try container.encode(value)
                            case .string(let value): try container.encode(value)
                            }
                        }

                        var intValue: Int? {
                            switch self {
                            case .int(let value): return value
                            case .string: return nil
                            }
                        }
                    }
                }
            }
        }
    }

    static func from(response: ListResponse) -> [KubernetesService] {
        response.items.map { item in
            KubernetesService(
                name: item.metadata.name,
                namespace: item.metadata.namespace,
                type: item.spec.type ?? "ClusterIP",
                clusterIP: item.spec.clusterIP,
                ports: item.spec.ports?.map { port in
                    ServicePort(
                        name: port.name,
                        port: port.port,
                        targetPort: port.targetPort?.intValue ?? port.port,
                        protocol: port.protocol
                    )
                } ?? []
            )
        }
    }
}
