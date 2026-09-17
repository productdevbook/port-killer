import AppKit
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
                    MissingToolBanner(tool: .cloudflared, message: "Share local ports on a public URL and run your named tunnels.")
                }
            } else if !tunnels.isLoggedIn {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not signed in to Cloudflare")
                                .fontWeight(.medium)
                            Text("Run cloudflared tunnel login in Terminal to list your account's tunnels. Quick tunnels work without an account.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
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
                    ProgressView("Looking for tunnels…")
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
                    Button("Stop Named Tunnels", systemImage: "stop.fill") { tunnels.stopAllNamedTunnels() }
                        .disabled(running.isEmpty)
                } label: {
                    Label("Stop", systemImage: "stop.circle")
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

struct QuickTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: QuickTunnel

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: tunnel.status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Port \(String(tunnel.port))")
                    .fontWeight(.medium)
                Text(tunnel.host ?? tunnel.lastError ?? tunnel.status.title)
                    .font(.caption)
                    .foregroundStyle(tunnel.status == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer()
            if let url = tunnel.url {
                Button("Copy URL", systemImage: "doc.on.doc") { Pasteboard.copy(url.absoluteString) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
            Button("Stop", systemImage: "stop.fill") { model.tunnels.stopQuickTunnel(tunnel) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
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

struct NamedTunnelRow: View {
    @Environment(AppModel.self) private var model
    let tunnel: NamedTunnel

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(color: tunnel.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.name)
                    .fontWeight(.medium)
                subtitle
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            if tunnel.status == .running {
                Text("\(tunnel.activeConnections) conn")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            control
        }
        .padding(.vertical, 4)
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
        } else if tunnel.runSafety == .managedElsewhere {
            Label("Managed elsewhere", systemImage: "lock.fill").foregroundStyle(.orange)
        } else if let first = tunnel.publicURLs.first {
            Text(tunnel.publicURLs.count > 1 ? "\(first) +\(tunnel.publicURLs.count - 1)" : first)
                .foregroundStyle(.secondary)
        } else {
            Text("No ingress rules").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var control: some View {
        switch tunnel.status {
        case .starting, .stopping:
            ProgressView().controlSize(.small)
        case .running:
            Button("Stop", systemImage: "stop.fill") { model.tunnels.stop(tunnel) }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        case .stopped, .failed:
            if tunnel.runSafety != .managedElsewhere {
                Button("Run", systemImage: "play.fill") { model.tunnels.run(tunnel) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(!model.tunnels.isInstalled)
            }
        }
    }
}

extension QuickTunnel.Status {
    var title: String {
        switch self {
        case .starting: "Starting…"
        case .active: "Active"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .starting, .stopping: .orange
        case .active: .green
        case .failed: .red
        }
    }
}

extension NamedTunnel {
    var statusTitle: String {
        switch status {
        case .stopped: runSafety == .managedElsewhere ? "Managed Elsewhere" : "Stopped"
        case .starting: "Starting…"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch status {
        case .running: .green
        case .starting, .stopping: .orange
        case .failed: .red
        case .stopped: runSafety == .managedElsewhere ? .orange : .secondary
        }
    }
}
