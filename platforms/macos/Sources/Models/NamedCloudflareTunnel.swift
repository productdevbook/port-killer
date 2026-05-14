import Foundation

// MARK: - Ingress Rule

/// A single ingress rule from a tunnel's configuration.
struct CloudflareTunnelIngressRule: Hashable, Sendable {
    let hostname: String?
    let path: String?
    let service: String

    init(hostname: String?, path: String? = nil, service: String) {
        self.hostname = hostname
        self.path = path
        self.service = service
    }

    /// Port number parsed out of `http://localhost:PORT` style services.
    var localPort: Int? {
        guard let url = URL(string: service), let port = url.port else { return nil }
        return port
    }

    var publicURL: String? {
        guard let hostname else { return nil }
        let normalizedPath: String
        if let path, !path.isEmpty {
            normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        } else {
            normalizedPath = ""
        }
        return "https://\(hostname)\(normalizedPath)"
    }
}

// MARK: - Remote Connection

/// A live edge connection reported by the Cloudflare control plane (from `tunnel list`).
struct CloudflareTunnelEdgeConnection: Hashable, Sendable {
    let id: String
    let coloName: String
    let originIP: String
    let openedAt: Date?
    let isPendingReconnect: Bool
}

// MARK: - Status

enum NamedTunnelStatus: String, Sendable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case stopping = "Stopping"
    case error = "Error"
}

// MARK: - Named Tunnel

/// A persistent (named) Cloudflare tunnel discovered from the local cloudflared config.
@Observable
@MainActor
final class NamedCloudflareTunnel: Identifiable, Sendable {
    /// Cloudflare tunnel UUID (stable identity).
    let tunnelID: String
    let name: String
    let createdAt: Date?

    /// Path to the credentials JSON in `~/.cloudflared/`, if present.
    var credentialsPath: String?

    /// Ingress rules parsed from local `config.yml`. May be empty for dashboard-managed tunnels
    /// until the first runtime config event arrives in the logs.
    var ingressRules: [CloudflareTunnelIngressRule] = []

    /// Source of the current ingress rules.
    var ingressSource: IngressSource = .none

    /// Sticky: true if this tunnel is referenced by the local `~/.cloudflared/config.yml`.
    /// Stays true even after the runtime config replaces `ingressRules`, so we don't
    /// mistakenly re-classify a locally-owned tunnel as `.managedElsewhere` once it
    /// connects to the edge and acquires its own connections.
    var hasLocalConfigMatch: Bool = false

    /// Live edge connections (from `cloudflared tunnel list`).
    var edgeConnections: [CloudflareTunnelEdgeConnection] = []

    // Runtime state when this app is running the tunnel locally:
    var runID: UUID?
    var status: NamedTunnelStatus = .stopped
    var startedAt: Date?
    var lastError: String?
    var metricsPort: Int?
    var activeConnectionCount: Int = 0
    var logs: [TunnelLogEntry] = []

    private static let maxLogEntries = 500

    nonisolated var id: String { tunnelID }

    init(tunnelID: String, name: String, createdAt: Date? = nil) {
        self.tunnelID = tunnelID
        self.name = name
        self.createdAt = createdAt
    }

    func addLogEntry(_ entry: TunnelLogEntry) {
        logs.append(entry)
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    enum IngressSource: String, Sendable {
        case none
        case localConfig
        case runtimeLog
    }

    // MARK: - Run Safety

    /// Whether it's safe (and useful) to run this tunnel from this machine.
    ///
    /// Cloudflare tunnels support multiple connectors per tunnel (HA / load-balancing),
    /// so running a tunnel that's already up on a VPS technically works — but on a dev
    /// laptop that's nearly always a footgun: the laptop becomes a second connector and
    /// edge requests get round-robined between origins that don't share the same backend
    /// services. We refuse to run those by default.
    enum RunSafety: Sendable, Equatable {
        /// Tunnel has local ingress config — safe to run here.
        case safe
        /// Tunnel has live edge connections from other machines and no local ingress.
        /// Running this would create a competing connector; we block the Run action.
        case managedElsewhere
        /// No edge connections anywhere and no local ingress — allowed, but the user
        /// likely needs to configure ingress first or the tunnel will just 404.
        case noIngress
    }

    var runSafety: RunSafety {
        // If we're the ones running it, it's safe by definition.
        if status == .running || status == .starting { return .safe }
        // User explicitly wired this tunnel into their local config.yml.
        if hasLocalConfigMatch { return .safe }
        // Edge connections from elsewhere → leave it alone.
        if !edgeConnections.isEmpty { return .managedElsewhere }
        return .noIngress
    }
}

extension NamedCloudflareTunnel: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(tunnelID)
    }

    nonisolated static func == (lhs: NamedCloudflareTunnel, rhs: NamedCloudflareTunnel) -> Bool {
        lhs.tunnelID == rhs.tunnelID
    }
}
