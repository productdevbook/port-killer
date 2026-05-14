import SwiftUI

/// Right-pane detail view for a selected named Cloudflare tunnel.
/// Shows full ingress mapping, edge connections, metadata, and live logs.
/// Mirrors the structure of `PortDetailView` so the two panes feel consistent.
struct NamedTunnelDetailView: View {
    let tunnel: NamedCloudflareTunnel
    @Environment(AppState.self) private var appState
    @State private var showLogs = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Divider()

                metaSection

                if !tunnel.ingressRules.isEmpty {
                    Divider()
                    ingressSection
                }

                if !tunnel.edgeConnections.isEmpty {
                    Divider()
                    edgeConnectionsSection
                }

                if tunnel.runSafety == .managedElsewhere {
                    Divider()
                    managedElsewhereExplanation
                }

                Divider()

                logsSection
            }
            .padding()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: "cloud.fill")
                        .font(.title2)
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tunnel.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(tunnel.status.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            statusBadges
            actionRow
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .running: .green
        case .starting, .stopping: .yellow
        case .error: .red
        case .stopped:
            tunnel.runSafety == .managedElsewhere ? .orange : .secondary
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 8) {
            badge(text: tunnel.status.rawValue, tint: statusColor)

            if tunnel.status == .running {
                badge(
                    text: "\(tunnel.activeConnectionCount) connections",
                    icon: "link",
                    tint: .green
                )
            }

            switch tunnel.runSafety {
            case .safe:
                if tunnel.hasLocalConfigMatch {
                    badge(text: "Local config", icon: "doc.text", tint: .blue)
                }
            case .managedElsewhere:
                badge(text: "Managed elsewhere", icon: "lock.fill", tint: .orange)
            case .noIngress:
                badge(text: "No ingress", icon: "exclamationmark.triangle", tint: .yellow)
            }

            Spacer()
        }
    }

    private func badge(text: String, icon: String? = nil, tint: Color) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.2))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            switch tunnel.status {
            case .stopped, .error:
                if tunnel.runSafety == .managedElsewhere {
                    Button {
                        appState.namedTunnelManager.run(tunnel, allowManagedElsewhere: true)
                    } label: {
                        Label("Run Anyway", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.orange)
                    .disabled(!appState.tunnelManager.isCloudflaredInstalled)
                    .help("Add this Mac as another connector for the tunnel")
                } else {
                    Button {
                        appState.namedTunnelManager.run(tunnel)
                    } label: {
                        Label("Run Tunnel", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!appState.tunnelManager.isCloudflaredInstalled)
                }
            case .starting, .stopping:
                Button {} label: {
                    HStack { ProgressView().controlSize(.small); Text(tunnel.status.rawValue) }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(true)
            case .running:
                Button {
                    appState.namedTunnelManager.stop(tunnel)
                } label: {
                    Label("Stop Tunnel", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            }
        }
    }

    // MARK: - Meta

    private var metaSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading)
        ], spacing: 16) {
            metaItem(label: "Tunnel ID", value: tunnel.tunnelID, monospaced: true)
            metaItem(label: "Ingress Source", value: ingressSourceLabel)
            if let created = tunnel.createdAt {
                metaItem(label: "Created", value: created.formatted(date: .abbreviated, time: .shortened))
            }
            if let metricsPort = tunnel.metricsPort {
                metaItem(label: "Metrics", value: "127.0.0.1:\(metricsPort)", monospaced: true)
            }
            if let started = tunnel.startedAt, tunnel.status == .running {
                metaItem(label: "Started", value: started.formatted(.relative(presentation: .named)))
            }
            if let credentials = tunnel.credentialsPath {
                metaItem(label: "Credentials", value: (credentials as NSString).abbreviatingWithTildeInPath, monospaced: true)
            }
        }
    }

    private var ingressSourceLabel: String {
        switch tunnel.ingressSource {
        case .none: return "—"
        case .localConfig: return "~/.cloudflared/config.yml"
        case .runtimeLog: return "Cloudflare dashboard"
        }
    }

    private func metaItem(label: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    // MARK: - Ingress

    private var ingressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ingress Rules")
                .font(.headline)

            VStack(spacing: 4) {
                ForEach(Array(tunnel.ingressRules.enumerated()), id: \.offset) { _, rule in
                    IngressRuleDetailRow(rule: rule)
                }
            }
        }
    }

    // MARK: - Edge Connections

    private var edgeConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Edge Connections")
                    .font(.headline)
                Text("\(tunnel.edgeConnections.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(tunnel.edgeConnections, id: \.id) { conn in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(conn.isPendingReconnect ? Color.yellow : Color.green)
                            .frame(width: 6, height: 6)
                        Text(conn.coloName)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .frame(minWidth: 60, alignment: .leading)
                        Text(conn.originIP)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let opened = conn.openedAt {
                            Text(opened, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Managed Elsewhere Explanation

    private var managedElsewhereExplanation: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("This tunnel is managed by another origin")
                    .font(.subheadline.weight(.semibold))
                Text("It has active edge connections from other machines and no local ingress configuration. Running it here adds this Mac as another connector, which can split traffic between origins. Use Run Anyway only if that is intentional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
    }

    // MARK: - Logs

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs")
                    .font(.headline)
                Spacer()
                if !tunnel.logs.isEmpty {
                    Text("\(tunnel.logs.count) entries")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button {
                        tunnel.clearLogs()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button {
                    showLogs.toggle()
                } label: {
                    Image(systemName: showLogs ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showLogs {
                if tunnel.logs.isEmpty {
                    Text(tunnel.status == .running ? "Waiting for output…" : "No logs yet. Run the tunnel to see live output.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    NamedTunnelLogView(tunnel: tunnel)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - Ingress Row (detail-pane variant)

private struct IngressRuleDetailRow: View {
    let rule: CloudflareTunnelIngressRule

    var body: some View {
        HStack(spacing: 10) {
            if let publicURL = rule.publicURL {
                Button {
                    if let url = URL(string: publicURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(publicURL)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.blue)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("(fallback)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(rule.service)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let publicURL = rule.publicURL {
                Button {
                    ClipboardService.copy(publicURL)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy URL")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Log View

struct NamedTunnelLogView: View {
    let tunnel: NamedCloudflareTunnel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(tunnel.logs) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.timestamp, style: .time)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.black.opacity(0.85))
            .onChange(of: tunnel.logs.count) { _, _ in
                if let last = tunnel.logs.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for level: TunnelLogEntry.LogLevel) -> Color {
        switch level {
        case .info: .white.opacity(0.85)
        case .warning: .orange
        case .error: .red
        case .request: .cyan
        }
    }
}
