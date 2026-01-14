import SwiftUI

struct CloudflareTunnelsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Dependency warning banner
            if !appState.tunnelManager.isCloudflaredInstalled {
                CloudflaredMissingBanner()
                Divider()
            }

            // Content
            if appState.tunnelManager.tunnels.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tunnelsList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Status bar
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Cloudflare Tunnels")
                .font(.headline)

            Spacer()

            if appState.tunnelManager.tunnels.count > 0 {
                Button {
                    Task {
                        await appState.tunnelManager.stopAllTunnels()
                    }
                } label: {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Active Tunnels", systemImage: "cloud")
        } description: {
            Text("Share a port via tunnel from the port list to create a public URL")
        }
    }

    // MARK: - Tunnels List

    private var tunnelsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.tunnelManager.tunnels) { tunnel in
                    CloudflareTunnelRow(tunnel: tunnel)
                    Divider()
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if appState.tunnelManager.activeTunnelCount > 0 {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("\(appState.tunnelManager.activeTunnelCount) active tunnel(s)")
            } else {
                Text("No active tunnels")
            }

            Spacer()

            if appState.tunnelManager.isCloudflaredInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("cloudflared installed")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Tunnel Row

struct CloudflareTunnelRow: View {
    let tunnel: CloudflareTunnelState
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isCopied = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator

            // Port info
            VStack(alignment: .leading, spacing: 2) {
                Text("Port " + String(tunnel.port))
                    .font(.headline)

                if let url = tunnel.tunnelURL {
                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                } else if tunnel.status == .starting {
                    Text("Starting tunnel...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = tunnel.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Actions
            if tunnel.status == .active, tunnel.tunnelURL != nil {
                actionButtons
            } else if tunnel.status == .starting {
                ProgressView()
                    .controlSize(.small)
            }

            // Stop button
            Button {
                appState.tunnelManager.stopTunnel(id: tunnel.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop tunnel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if tunnel.status == .active, let url = tunnel.tunnelURL {
                Button {
                    ClipboardService.copy(url)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }

                Button {
                    if let tunnelURL = URL(string: url) {
                        NSWorkspace.shared.open(tunnelURL)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "globe")
                }

                Divider()
            }

            Button(role: .destructive) {
                appState.tunnelManager.stopTunnel(id: tunnel.id)
            } label: {
                Label("Stop Tunnel", systemImage: "stop.fill")
            }
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .idle: .secondary
        case .starting: .yellow
        case .active: .green
        case .stopping: .yellow
        case .error: .red
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                if let url = tunnel.tunnelURL {
                    ClipboardService.copy(url)
                    isCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        isCopied = false
                    }
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy URL")

            Button {
                if let url = tunnel.tunnelURL, let tunnelURL = URL(string: url) {
                    NSWorkspace.shared.open(tunnelURL)
                }
            } label: {
                Image(systemName: "globe")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open in Browser")
        }
    }
}
