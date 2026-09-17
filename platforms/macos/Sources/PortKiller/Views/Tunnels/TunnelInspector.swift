import AppKit
import PortKillerKit
import SwiftUI

struct TunnelInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.tunnels.selection {
        case .quick(let id):
            if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == id }) {
                QuickTunnelDetails(tunnel: tunnel)
                    .id(id)
            } else {
                empty
            }
        case .named(let id):
            if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == id }) {
                NamedTunnelDetails(tunnel: tunnel)
                    .id(id)
            } else {
                empty
            }
        case nil:
            empty
        }
    }

    private var empty: some View {
        ContentUnavailableView("No Tunnel Selected", systemImage: "cloud", description: Text("Select a tunnel to see its routes, connections and logs."))
    }
}

private struct QuickTunnelDetails: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    QuickTunnelSummary(tunnel: tunnel)
                }
                Section("Details") {
                    LabeledContent("Local Port", value: String(tunnel.port))
                    LabeledContent("Status", value: tunnel.status.title)
                    if let startedAt = tunnel.startedAt {
                        LabeledContent("Started") {
                            Text(startedAt, format: .relative(presentation: .named))
                        }
                    }
                    LabeledContent("Protocol", value: model.preferences.quickTunnelProtocol.title)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 280)
            LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "cloudflared output appears here.")
        }
    }
}

private struct NamedTunnelDetails: View {
    enum Page: String, CaseIterable {
        case details = "Details"
        case logs = "Logs"
    }

    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel
    @State private var page = Page.details

    var body: some View {
        VStack(spacing: 0) {
            header
            InspectorSegmentedPicker(selection: $page, options: Page.allCases) { $0 == .logs && !tunnel.logs.isEmpty ? "Logs (\(tunnel.logs.count))" : $0.rawValue }
            switch page {
            case .details:
                details
            case .logs:
                LogConsole(lines: tunnel.logs.map(\.consoleLine), emptyText: "Run the tunnel to see cloudflared output.", onClear: { tunnel.clearLogs() })
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.title2)
                    .foregroundStyle(tunnel.tint)
                    .frame(width: 40, height: 40)
                    .background(tunnel.tint.opacity(0.15), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tunnel.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(tunnel.status == .running ? "\(tunnel.statusTitle) · \(tunnel.activeConnections) connections" : tunnel.statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            actionButton
            if let error = tunnel.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch tunnel.status {
        case .running:
            Button(role: .destructive) { model.tunnels.stop(tunnel) } label: {
                Label("Stop Tunnel", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
        case .starting, .stopping:
            Button {} label: {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(tunnel.statusTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(true)
        case .stopped, .failed:
            if tunnel.runSafety == .managedElsewhere {
                Button { model.tunnels.run(tunnel, allowManagedElsewhere: true) } label: {
                    Label("Run Anyway", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .tint(.orange)
                .controlSize(.large)
                .disabled(!model.tunnels.isInstalled)
                .help("Add this Mac as another connector for the tunnel")
            } else {
                Button { model.tunnels.run(tunnel) } label: {
                    Label("Run Tunnel", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.tunnels.isInstalled)
            }
        }
    }

    private var details: some View {
        Form {
            if tunnel.runSafety == .managedElsewhere {
                Section {
                    Label {
                        Text("Other machines already run this tunnel and this Mac has no local configuration for it. Running it here adds another connector, which splits traffic between origins.")
                            .font(.callout)
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                    }
                }
            }
            if !tunnel.ingressRules.isEmpty {
                Section("Routes") {
                    ForEach(Array(tunnel.ingressRules.enumerated()), id: \.offset) { _, rule in
                        VStack(alignment: .leading, spacing: 2) {
                            if let url = rule.publicURL {
                                Button(url) {
                                    if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                                }
                                .buttonStyle(.link)
                                .contextMenu {
                                    Button("Copy URL") { Pasteboard.copy(url) }
                                }
                            } else {
                                Text("Fallback").foregroundStyle(.secondary)
                            }
                            Label(rule.service, systemImage: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            Section("Details") {
                LabeledContent("Tunnel ID") {
                    Text(tunnel.id)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("Routes From", value: ingressSource)
                if let created = tunnel.createdAt {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let metricsPort = tunnel.metricsPort {
                    LabeledContent("Metrics", value: "127.0.0.1:\(metricsPort)")
                }
                if let credentials = tunnel.credentialsPath {
                    LabeledContent("Credentials", value: (credentials as NSString).abbreviatingWithTildeInPath)
                }
            }
            if !tunnel.edgeConnections.isEmpty {
                Section("Edge Connections") {
                    ForEach(tunnel.edgeConnections) { connection in
                        HStack {
                            StatusDot(color: connection.isPendingReconnect ? .orange : .green, size: 6)
                            Text(connection.coloName)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                            Text(connection.originIP)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let opened = connection.openedAt {
                                Text(opened, format: .relative(presentation: .named))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var ingressSource: String {
        switch tunnel.ingressSource {
        case .none: "Unknown"
        case .localConfiguration: "~/.cloudflared/config.yml"
        case .dashboard: "Cloudflare dashboard"
        }
    }
}
