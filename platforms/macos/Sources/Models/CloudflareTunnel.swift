import Foundation

// MARK: - Tunnel Status

/// Status of a Cloudflare tunnel
enum CloudflareTunnelStatus: String, Sendable {
    case idle = "Idle"
    case starting = "Starting..."
    case active = "Active"
    case stopping = "Stopping..."
    case error = "Error"

    var icon: String {
        switch self {
        case .idle: "circle"
        case .starting: "circle.dotted"
        case .active: "circle.fill"
        case .stopping: "circle.dotted"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Tunnel State

/// Runtime state for a Cloudflare Quick Tunnel (ephemeral - not persisted)
@Observable
@MainActor
final class CloudflareTunnelState: Identifiable, Sendable {
    let id: UUID
    let port: Int
    let portInfoId: UUID?
    var status: CloudflareTunnelStatus = .idle
    var tunnelURL: String?
    var lastError: String?
    var startTime: Date?

    init(id: UUID = UUID(), port: Int, portInfoId: UUID? = nil) {
        self.id = id
        self.port = port
        self.portInfoId = portInfoId
    }
}

extension CloudflareTunnelState: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: CloudflareTunnelState, rhs: CloudflareTunnelState) -> Bool {
        lhs.id == rhs.id
    }
}
