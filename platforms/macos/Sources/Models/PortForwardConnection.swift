import Foundation
import Defaults

// MARK: - Connection Configuration

/// Configuration for a Kubernetes port-forward connection
/// Persisted using Defaults library
struct PortForwardConnectionConfig: Identifiable, Codable, Equatable, Hashable, Sendable, Defaults.Serializable {
    let id: UUID
    var name: String
    var namespace: String
    var service: String
    var localPort: Int
    var remotePort: Int
    var proxyPort: Int?
    var isEnabled: Bool
    var autoReconnect: Bool
    /// Direct exec mode: Uses kubectl exec + socat for true multi-connection support
    var useDirectExec: Bool
    /// Notification settings
    var notifyOnConnect: Bool
    var notifyOnDisconnect: Bool

    init(
        id: UUID = UUID(),
        name: String,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int,
        proxyPort: Int? = nil,
        isEnabled: Bool = true,
        autoReconnect: Bool = true,
        useDirectExec: Bool = true,
        notifyOnConnect: Bool = true,
        notifyOnDisconnect: Bool = true
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.service = service
        self.localPort = localPort
        self.remotePort = remotePort
        self.proxyPort = proxyPort
        self.isEnabled = isEnabled
        self.autoReconnect = autoReconnect
        self.useDirectExec = useDirectExec
        self.notifyOnConnect = notifyOnConnect
        self.notifyOnDisconnect = notifyOnDisconnect
    }

    // MARK: - Codable Migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        namespace = try container.decode(String.self, forKey: .namespace)
        service = try container.decode(String.self, forKey: .service)
        localPort = try container.decode(Int.self, forKey: .localPort)
        remotePort = try container.decode(Int.self, forKey: .remotePort)
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        autoReconnect = try container.decode(Bool.self, forKey: .autoReconnect)
        useDirectExec = try container.decode(Bool.self, forKey: .useDirectExec)

        // New fields with defaults for migration
        notifyOnConnect = try container.decodeIfPresent(Bool.self, forKey: .notifyOnConnect) ?? true
        notifyOnDisconnect = try container.decodeIfPresent(Bool.self, forKey: .notifyOnDisconnect) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, namespace, service, localPort, remotePort, proxyPort
        case isEnabled, autoReconnect, useDirectExec
        case notifyOnConnect, notifyOnDisconnect
    }
}

// MARK: - Connection Status

enum PortForwardStatus: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case error = "Error"

    var icon: String {
        switch self {
        case .disconnected: "circle"
        case .connecting: "circle.dotted"
        case .connected: "circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .disconnected: "secondary"
        case .connecting: "yellow"
        case .connected: "green"
        case .error: "red"
        }
    }
}

// MARK: - Connection Runtime State

/// A single log entry for a port-forward connection
struct PortForwardLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: PortForwardProcessType
    let isError: Bool
}

/// Runtime state for a port-forward connection (not persisted)
@Observable
@MainActor
final class PortForwardConnectionState: Identifiable, Hashable {
    let id: UUID
    var config: PortForwardConnectionConfig
    var portForwardStatus: PortForwardStatus = .disconnected
    var proxyStatus: PortForwardStatus = .disconnected
    var portForwardTask: Task<Void, Never>?
    var proxyTask: Task<Void, Never>?
    var lastError: String?
    var logs: [PortForwardLogEntry] = []
    /// Tracks if the connection was stopped intentionally by the user (vs unexpected disconnect)
    var isIntentionallyStopped: Bool = false

    func appendLog(_ message: String, type: PortForwardProcessType, isError: Bool = false) {
        let entry = PortForwardLogEntry(timestamp: Date(), message: message, type: type, isError: isError)
        logs.append(entry)
        // Keep only last 500 log entries
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    /// Whether the connection is fully established (port-forward + optional proxy)
    var isFullyConnected: Bool {
        if config.proxyPort != nil {
            return portForwardStatus == .connected && proxyStatus == .connected
        }
        return portForwardStatus == .connected
    }

    /// The effective port that clients should connect to
    var effectivePort: Int {
        config.proxyPort ?? config.localPort
    }

    init(id: UUID, config: PortForwardConnectionConfig) {
        self.id = id
        self.config = config
    }

    init(config: PortForwardConnectionConfig) {
        self.id = config.id
        self.config = config
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: PortForwardConnectionState, rhs: PortForwardConnectionState) -> Bool {
        lhs.id == rhs.id
    }
}
