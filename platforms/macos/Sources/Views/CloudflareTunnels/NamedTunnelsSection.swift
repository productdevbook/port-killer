import SwiftUI

// MARK: - Section

/// Compact list of persistent (named) Cloudflare tunnels.
/// Selecting a row routes detail to `NamedTunnelDetailView` in the right pane,
/// matching how the All Ports view uses the detail column.
///
/// Rows are grouped by actionability — **Running** / **Available** /
/// **Managed Elsewhere** — using simple section labels (no card backgrounds)
/// so the look stays consistent with the rest of the app.
struct NamedTunnelsSection: View {
    @Environment(AppState.self) private var appState
    @State private var managedElsewhereExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.namedTunnelManager.isLoggedIn && !appState.namedTunnelManager.tunnels.isEmpty {
                loginWarning
            }

            if appState.namedTunnelManager.tunnels.isEmpty {
                if appState.namedTunnelManager.isDiscovering {
                    discoveringRow
                } else if !appState.namedTunnelManager.isLoggedIn {
                    placeholderMessage(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "Not logged in to Cloudflare",
                        detail: "Run `cloudflared tunnel login` in Terminal to list account tunnels. Local tunnel credentials and config are still supported when present."
                    )
                } else {
                    placeholderMessage(
                        icon: "cloud",
                        title: "No tunnels yet",
                        detail: "Create one with `cloudflared tunnel create <name>` or via the Cloudflare dashboard."
                    )
                }
            } else {
                if !running.isEmpty {
                    sectionLabel("Running", count: running.count)
                    ForEach(running) { tunnel in
                        NamedTunnelRow(tunnel: tunnel)
                        Divider().padding(.leading, 32)
                    }
                }
                if !available.isEmpty {
                    sectionLabel("Available", count: available.count)
                    ForEach(available) { tunnel in
                        NamedTunnelRow(tunnel: tunnel)
                        Divider().padding(.leading, 32)
                    }
                }
                if !managedElsewhere.isEmpty {
                    managedElsewhereGroup
                }
            }
        }
    }

    // MARK: - Groupings

    private var running: [NamedCloudflareTunnel] {
        appState.namedTunnelManager.tunnels.filter {
            $0.status == .running || $0.status == .starting
        }
    }

    private var available: [NamedCloudflareTunnel] {
        appState.namedTunnelManager.tunnels.filter {
            ($0.status == .stopped || $0.status == .error) && $0.runSafety != .managedElsewhere
        }
    }

    private var managedElsewhere: [NamedCloudflareTunnel] {
        appState.namedTunnelManager.tunnels.filter {
            $0.status != .running && $0.status != .starting && $0.runSafety == .managedElsewhere
        }
    }

    // MARK: - Subviews

    private func sectionLabel(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var managedElsewhereGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    managedElsewhereExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(managedElsewhereExpanded ? 90 : 0))
                    Text("Managed Elsewhere")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text("\(managedElsewhere.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if managedElsewhereExpanded {
                ForEach(managedElsewhere) { tunnel in
                    NamedTunnelRow(tunnel: tunnel)
                    Divider().padding(.leading, 32)
                }
            }
        }
    }

    private func placeholderMessage(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var loginWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Cloudflare account login not found")
                    .font(.caption.weight(.semibold))
                Text("Showing locally configured tunnels only. Run `cloudflared tunnel login` to discover all account tunnels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }

    private var discoveringRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Discovering tunnels…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}

// MARK: - Named Tunnel Row

/// Compact list row for a named tunnel. Matches the visual weight of
/// `PortListRow`: status dot + name + subtitle + trailing actions. No card
/// background; selection state is communicated via background tint.
struct NamedTunnelRow: View {
    let tunnel: NamedCloudflareTunnel
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    private var isSelected: Bool {
        appState.selectedNamedTunnelID == tunnel.tunnelID
    }

    var body: some View {
        HStack(spacing: 10) {
            statusDot

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .font(.body)
                    .lineLimit(1)

                subtitle
            }

            Spacer(minLength: 8)

            if tunnel.status == .running {
                Text("\(tunnel.activeConnectionCount) conn")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            trailingControl
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectedNamedTunnelID = tunnel.tunnelID
        }
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu }
    }

    // MARK: - Subviews

    private var statusDot: some View {
        StatusDot(color: statusColor)
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

    @ViewBuilder
    private var subtitle: some View {
        let routes = tunnel.ingressRules.compactMap { $0.publicURL }
        if tunnel.status == .error, let error = tunnel.lastError {
            Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
        } else if tunnel.status == .starting {
            Text("Starting…").font(.caption).foregroundStyle(.secondary)
        } else if tunnel.runSafety == .managedElsewhere {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Managed elsewhere")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let first = routes.first {
            HStack(spacing: 4) {
                Text(first)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if routes.count > 1 {
                    Text("+\(routes.count - 1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            Text("No ingress configured").font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch tunnel.status {
        case .stopped, .error:
            if tunnel.runSafety != .managedElsewhere {
                Button {
                    appState.namedTunnelManager.run(tunnel)
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!appState.tunnelManager.isCloudflaredInstalled)
                .help("Run this tunnel")
            }
        case .starting, .stopping:
            ProgressView().controlSize(.small)
        case .running:
            Button {
                appState.namedTunnelManager.stop(tunnel)
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .help("Stop this tunnel")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if tunnel.status == .running {
            Button(role: .destructive) {
                appState.namedTunnelManager.stop(tunnel)
            } label: { Label("Stop Tunnel", systemImage: "stop.fill") }
        } else if tunnel.runSafety == .managedElsewhere {
            Button {
                appState.namedTunnelManager.run(tunnel, allowManagedElsewhere: true)
            } label: { Label("Run Anyway", systemImage: "play.fill") }
        } else if tunnel.runSafety != .managedElsewhere {
            Button {
                appState.namedTunnelManager.run(tunnel)
            } label: { Label("Run Tunnel", systemImage: "play.fill") }
        }
        Divider()
        Button {
            ClipboardService.copy(tunnel.tunnelID)
        } label: { Label("Copy Tunnel ID", systemImage: "doc.on.doc") }
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.2)
            } else if isHovered {
                Color.primary.opacity(0.05)
            } else {
                Color.clear
            }
        }
    }
}
