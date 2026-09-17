public import Foundation

public struct TunnelIngressRule: Hashable, Sendable {
    public var hostname: String?
    public var path: String?
    public var service: String

    public init(hostname: String?, path: String? = nil, service: String) {
        self.hostname = hostname
        self.path = path
        self.service = service
    }

    public var localPort: Int? {
        URL(string: service)?.port
    }

    public var publicURL: String? {
        guard let hostname else { return nil }
        guard let path, !path.isEmpty else { return "https://\(hostname)" }
        return "https://\(hostname)\(path.hasPrefix("/") ? path : "/\(path)")"
    }
}

public struct TunnelEdgeConnection: Hashable, Sendable, Identifiable {
    public var id: String
    public var coloName: String
    public var originIP: String
    public var openedAt: Date?
    public var isPendingReconnect: Bool
}

public struct DiscoveredTunnel: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date?
    public var credentialsPath: String?
    public var edgeConnections: [TunnelEdgeConnection]
    public var localIngress: [TunnelIngressRule]
}

public enum TunnelRunSafety: Sendable, Equatable {
    case safe
    case managedElsewhere
    case noIngress

    public static func evaluate(isRunningHere: Bool, hasLocalConfig: Bool, edgeConnectionCount: Int) -> TunnelRunSafety {
        if isRunningHere || hasLocalConfig { return .safe }
        return edgeConnectionCount > 0 ? .managedElsewhere : .noIngress
    }
}

public enum QuickTunnelProtocol: String, CaseIterable, Identifiable, Sendable, Codable {
    case http2
    case quic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .http2: "HTTP/2"
        case .quic: "QUIC"
        }
    }
}

public enum TunnelLogLevel: Sendable, Hashable {
    case info
    case request
    case warning
    case error

    public static func classify(_ line: String) -> TunnelLogLevel {
        let lowercased = line.lowercased()
        if ["error", "failed", "unable to", " err "].contains(where: lowercased.contains) || lowercased.contains(" err=") { return .error }
        if lowercased.contains("warn") || lowercased.contains(" wrn ") { return .warning }
        if ["request", "get ", "post ", "put ", "delete ", "patch ", "status="].contains(where: lowercased.contains) { return .request }
        return .info
    }
}

public struct TunnelLogEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var message: String
    public var level: TunnelLogLevel

    public init(message: String) {
        id = UUID()
        date = Date()
        self.message = message
        level = TunnelLogLevel.classify(message)
    }
}
