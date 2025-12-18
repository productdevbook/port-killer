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
        useDirectExec: Bool = true
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
