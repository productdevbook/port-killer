import PortKillerKit
import SwiftUI

struct QuickTunnelInfoInspector: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        Form {
            Section {
                InfoRow(title: "Status", value: tunnel.status.title)
                if let url = tunnel.url {
                    InfoRow(title: "Address", value: url.absoluteString)
                }
                InfoRow(title: "Local Port", value: String(tunnel.port))
                if let startedAt = tunnel.startedAt {
                    InfoRow(title: "Started", value: startedAt.formatted(date: .omitted, time: .shortened))
                }
                InfoRow(title: "Protocol", value: model.preferences.quickTunnelProtocol.title)
                if let error = tunnel.lastError, tunnel.status != .active {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Tunnel")
            } footer: {
                Text("Quick tunnels get a random trycloudflare.com address and stop when PortKiller quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct NamedTunnelInfoInspector: View {
    let tunnel: NamedTunnel

    var body: some View {
        Form {
            Section {
                InfoRow(title: "Status", value: tunnel.statusTitle)
                if let error = tunnel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            } footer: {
                if tunnel.runSafety == .managedElsewhere, !tunnel.isRunningHere {
                    Text("Other machines already run this tunnel and this Mac has no local configuration for it. Running it here adds another connector, which splits traffic between origins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !tunnel.ingressRules.isEmpty {
                Section("Routes") {
                    ForEach(Array(tunnel.ingressRules.enumerated()), id: \.offset) { _, rule in
                        InfoRow(title: rule.hostname.map { hostname in rule.path.map { "\(hostname)\($0)" } ?? hostname } ?? "Everything Else", value: rule.service)
                    }
                }
            }

            Section("Details") {
                InfoRow(title: "Tunnel ID", value: tunnel.id)
                InfoRow(title: "Routes From", value: ingressSource)
                if let created = tunnel.createdAt {
                    InfoRow(title: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let metricsPort = tunnel.metricsPort {
                    InfoRow(title: "Metrics", value: "127.0.0.1:\(metricsPort)")
                }
                if let credentials = tunnel.credentialsPath {
                    InfoRow(title: "Credentials", value: (credentials as NSString).abbreviatingWithTildeInPath)
                }
            }

            if !tunnel.edgeConnections.isEmpty {
                Section("Edge Connections") {
                    ForEach(tunnel.edgeConnections) { connection in
                        InfoRow(
                            title: connection.coloName,
                            value: [connection.originIP, connection.isPendingReconnect ? "Reconnecting" : nil].compactMap { $0 }.joined(separator: " · ")
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var ingressSource: String {
        switch tunnel.ingressSource {
        case .none: "Unknown"
        case .localConfiguration: "config.yml"
        case .dashboard: "Dashboard"
        }
    }
}
