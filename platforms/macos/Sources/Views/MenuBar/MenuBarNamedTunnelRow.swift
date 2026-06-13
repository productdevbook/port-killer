import SwiftUI

/// Compact menu-bar row for a persistent (named) Cloudflare tunnel.
/// Provides Run/Stop controls and shows a one-line ingress summary.
struct MenuBarNamedTunnelRow: View {
    let tunnel: NamedCloudflareTunnel
    @Bindable var state: AppState
    @State private var isHovered = false

    private var primaryRoute: String? {
        tunnel.ingressRules.compactMap { $0.publicURL }.first
    }

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: tunnel.status.color, size: Sizing.statusDotSmall, glow: tunnel.status == .running)

            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                subtitle
            }

            Spacer()

            if tunnel.status == .running {
                Text("\(tunnel.activeConnectionCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.green)
                    .help("\(tunnel.activeConnectionCount) active edge connections")
            }

            trailingControls
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var subtitle: some View {
        if tunnel.runSafety == .managedElsewhere {
            Text("Managed elsewhere")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if tunnel.status == .starting {
            Text("Starting…").font(.caption2).foregroundStyle(.secondary)
        } else if tunnel.status == .running {
            Text(tunnel.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if tunnel.ingressRules.isEmpty {
            Text("No ingress").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Text("\(tunnel.ingressRules.compactMap { $0.publicURL }.count) route(s)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        switch tunnel.status {
        case .stopped, .error:
            if tunnel.runSafety != .managedElsewhere {
                Button {
                    state.namedTunnelManager.run(tunnel)
                } label: {
                    Image(systemName: "play.fill").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .opacity(isHovered ? 1 : 0.7)
                .help("Run tunnel")
            }
        case .starting, .stopping:
            ProgressView().scaleEffect(0.5).frame(width: 14, height: 14)
        case .running:
            Button {
                state.namedTunnelManager.stop(tunnel)
            } label: {
                Image(systemName: "stop.fill").font(.caption).foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.7)
            .help("Stop tunnel")
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if tunnel.status == .running {
            Button(role: .destructive) {
                state.namedTunnelManager.stop(tunnel)
            } label: { Label("Stop Tunnel", systemImage: "stop.fill") }
        } else if tunnel.runSafety != .managedElsewhere {
            Button {
                state.namedTunnelManager.run(tunnel)
            } label: { Label("Run Tunnel", systemImage: "play.fill") }
        }
        if let route = primaryRoute {
            Divider()
            Button {
                if let url = URL(string: route) {
                    NSWorkspace.shared.open(url)
                }
            } label: { Label("Open \(route)", systemImage: "globe") }
        }
    }
}
