import Foundation

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
