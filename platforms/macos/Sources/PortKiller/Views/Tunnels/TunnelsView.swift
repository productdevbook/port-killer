import PortKillerKit
import SwiftUI

struct TunnelsView: View {
    @Environment(AppModel.self) private var model
    @State private var showManagedElsewhere = false

    var body: some View {
        @Bindable var tunnels = model.tunnels
        let named = tunnels.namedTunnels
        let running = named.filter(\.isRunningHere)
        let available = named.filter { !$0.isRunningHere && $0.runSafety != .managedElsewhere }
        let elsewhere = named.filter { !$0.isRunningHere && $0.runSafety == .managedElsewhere }
        let isInstalled = tunnels.isInstalled

        List(selection: $tunnels.selection) {
            if !isInstalled {
                Section {
                    ToolNotice(tool: .cloudflared, message: "Share local ports on a public URL and run your named tunnels.")
                }
            } else if !tunnels.isLoggedIn {
                Section {
                    NoticeRow(symbol: "person.crop.circle.badge.exclamationmark", title: "Not Signed In to Cloudflare", message: "Run cloudflared tunnel login to list your account's tunnels. Quick tunnels work without an account.") {
                        Button("Copy Login Command") { Pasteboard.copy("cloudflared tunnel login") }
                    }
                }
            }

            if !tunnels.quickTunnels.isEmpty {
                Section("Quick Tunnels") {
                    ForEach(tunnels.quickTunnels) { tunnel in
                        QuickTunnelRow(tunnel: tunnel)
                            .tag(TunnelSelection.quick(tunnel.id))
                    }
                }
            }
            if !running.isEmpty {
                Section("Running") {
                    ForEach(running) { NamedTunnelRow(tunnel: $0).tag(TunnelSelection.named($0.id)) }
                }
            }
            if !available.isEmpty {
                Section("Available") {
                    ForEach(available) { NamedTunnelRow(tunnel: $0).tag(TunnelSelection.named($0.id)) }
                }
            }
            if !elsewhere.isEmpty {
                Section(isExpanded: $showManagedElsewhere) {
                    ForEach(elsewhere) { NamedTunnelRow(tunnel: $0).tag(TunnelSelection.named($0.id)) }
                } header: {
                    Text("Managed Elsewhere")
                }
            }
        }
        .overlay {
            if isInstalled, named.isEmpty, tunnels.quickTunnels.isEmpty {
                if tunnels.isDiscovering {
                    ProgressView()
                } else {
                    ContentUnavailableView {
                        Label("No Tunnels", systemImage: "cloud")
                    } description: {
                        Text("Share a port from its context menu for a quick trycloudflare.com URL, or create a named tunnel with cloudflared tunnel create.")
                    }
                }
            }
        }
        .navigationTitle("Cloudflare Tunnels")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button("Stop Quick Tunnels", systemImage: "bolt.slash") { tunnels.stopAllQuickTunnels() }
                        .disabled(tunnels.quickTunnels.isEmpty)
                    Button("Stop Named Tunnels", systemImage: "stop") { tunnels.stopAllNamedTunnels() }
                        .disabled(running.isEmpty)
                } label: {
                    Label("Stop", systemImage: "stop")
                }
                .menuIndicator(.hidden)
                .disabled(tunnels.quickTunnels.isEmpty && running.isEmpty)
                .help("Stop tunnels")

                Button("Refresh", systemImage: "arrow.clockwise") {
                    tunnels.recheckInstallation()
                    tunnels.discover()
                }
                .disabled(tunnels.isDiscovering)
                .help("Look for tunnels again")
            }
        }
        .onAppear { tunnels.startDiscovery() }
        .onDisappear { tunnels.stopDiscovery() }
    }

    private var subtitle: String {
        let tunnels = model.tunnels
        var parts: [String] = []
        if tunnels.runningNamedCount > 0 { parts.append("\(tunnels.runningNamedCount) running") }
        if tunnels.activeQuickCount > 0 { parts.append("\(tunnels.activeQuickCount) quick") }
        return parts.joined(separator: " · ")
    }
}

private struct QuickTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: "bolt", tint: tunnel.status.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Port \(String(tunnel.port))")
                    .lineLimit(1)
                Text(tunnel.host ?? tunnel.lastError ?? tunnel.status.title)
                    .font(.subheadline)
                    .foregroundStyle(tunnel.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let url = tunnel.url {
                URLActions(url: url)
                Divider()
            }
            Button("Stop Tunnel", role: .destructive) { model.tunnels.stopQuickTunnel(tunnel) }
        }
    }
}

private struct NamedTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(symbol: "cloud", tint: tunnel.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(tunnel.name)
                    .lineLimit(1)
                subtitle
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .opacity(tunnel.runSafety == .managedElsewhere && !tunnel.isRunningHere ? 0.55 : 1)
        .contextMenu {
            if tunnel.isRunningHere {
                Button("Stop Tunnel", role: .destructive) { model.tunnels.stop(tunnel) }
            } else if tunnel.runSafety == .managedElsewhere {
                Button("Run Anyway") { model.tunnels.run(tunnel, allowManagedElsewhere: true) }
            } else {
                Button("Run Tunnel") { model.tunnels.run(tunnel) }
            }
            Divider()
            Button("Copy Tunnel ID") { Pasteboard.copy(tunnel.id) }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if tunnel.status == .failed, let error = tunnel.lastError {
            Text(error).foregroundStyle(.red)
        } else if tunnel.isRunningHere || tunnel.runSafety == .managedElsewhere {
            Text(tunnel.statusTitle).foregroundStyle(.secondary)
        } else if let first = tunnel.publicURLs.first {
            Text(tunnel.publicURLs.count > 1 ? "\(first) +\(tunnel.publicURLs.count - 1)" : first)
                .foregroundStyle(.secondary)
        } else {
            Text("No ingress rules").foregroundStyle(.secondary)
        }
    }
}
