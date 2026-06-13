import SwiftUI

// MARK: - Cloudflare Tunnels View

/// List pane for the Cloudflare Tunnels sidebar item.
/// Composed of the named (persistent) tunnels list and, when present, a Quick
/// Tunnels strip below. Detail for the selected tunnel renders in the right
/// pane via `NamedTunnelDetailView` (wired in `MainWindowView`).
struct CloudflareTunnelsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if !appState.tunnelManager.isCloudflaredInstalled {
                CloudflaredMissingBanner()
                Divider()
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    NamedTunnelsSection()

                    if !appState.tunnelManager.tunnels.isEmpty {
                        quickTunnelsSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appState.namedTunnelManager.startRefreshing()
        }
        .onDisappear {
            appState.namedTunnelManager.stopRefreshing()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Cloudflare Tunnels")
                .font(.headline)

            Spacer()

            Button {
                appState.namedTunnelManager.discover(force: true)
            } label: {
                if appState.namedTunnelManager.isDiscovering {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh tunnel list")
            .disabled(appState.namedTunnelManager.isDiscovering)

            if appState.namedTunnelManager.runningCount > 0 || appState.tunnelManager.activeTunnelCount > 0 {
                Menu {
                    if appState.namedTunnelManager.runningCount > 0 {
                        Button(role: .destructive) {
                            Task { await appState.namedTunnelManager.stopAll() }
                        } label: { Label("Stop All My Tunnels", systemImage: "stop.fill") }
                    }
                    if appState.tunnelManager.activeTunnelCount > 0 {
                        Button(role: .destructive) {
                            Task { await appState.tunnelManager.stopAllTunnels() }
                        } label: { Label("Stop All Quick Tunnels", systemImage: "stop.fill") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusSummary(running: Int, quick: Int) -> String {
        var parts: [String] = []
        if running > 0 { parts.append("\(running) running") }
        if quick > 0 { parts.append("\(quick) quick") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        let running = appState.namedTunnelManager.runningCount
        let quick = appState.tunnelManager.activeTunnelCount
        return HStack(spacing: 12) {
            if running > 0 || quick > 0 {
                StatusDot(color: Theme.Colors.statusSuccess)
                Text(statusSummary(running: running, quick: quick))
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

    // MARK: - Quick Tunnels Section

    @ViewBuilder
    private var quickTunnelsSection: some View {
        HStack(spacing: 6) {
            Text("Quick Tunnels")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(appState.tunnelManager.tunnels.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)

        ForEach(appState.tunnelManager.tunnels) { tunnel in
            CloudflareTunnelRow(tunnel: tunnel)
            Divider().padding(.leading, 32)
        }
    }
}

// MARK: - Quick Tunnel Row

struct CloudflareTunnelRow: View {
    let tunnel: CloudflareTunnelState
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var showLogs = false

    var body: some View {
        VStack(spacing: 0) {
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

                // Log toggle
                Button {
                    showLogs.toggle()
                } label: {
                    Image(systemName: "doc.text")
                        .foregroundColor(showLogs ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showLogs ? "Hide logs" : "Show logs")

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

            if showLogs {
                Divider()
                TunnelLogView(tunnel: tunnel)
                    .frame(height: 200)
            }
        }
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
        .contextMenu {
            if tunnel.status == .active, let url = tunnel.tunnelURL {
                Button {
                    ClipboardService.copy(url)
                } label: { Label("Copy URL", systemImage: "doc.on.doc") }
                Button {
                    if let tunnelURL = URL(string: url) {
                        NSWorkspace.shared.open(tunnelURL)
                    }
                } label: { Label("Open in Browser", systemImage: "globe") }
                Divider()
            }
            Button {
                showLogs.toggle()
            } label: { Label(showLogs ? "Hide Logs" : "Show Logs", systemImage: "doc.text") }
            Divider()
            Button(role: .destructive) {
                appState.tunnelManager.stopTunnel(id: tunnel.id)
            } label: { Label("Stop Tunnel", systemImage: "stop.fill") }
        }
    }

    private var statusIndicator: some View {
        StatusDot(color: tunnel.status.color)
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
