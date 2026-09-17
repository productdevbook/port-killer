import PortKillerKit
import SwiftUI

struct TunnelsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showTunnelsManagedElsewhere") private var showManagedElsewhere = false

    var body: some View {
        @Bindable var model = model
        let tunnels = model.tunnels
        let query = model.ports.filter.searchText.trimmingCharacters(in: .whitespaces)
        let rows = (tunnels.quickTunnels.map(TunnelRow.init) + tunnels.namedTunnels
            .filter { $0.isRunningHere || showManagedElsewhere || $0.runSafety != .managedElsewhere }
            .map(TunnelRow.init))
            .filter { $0.matches(query) }

        Table(rows, selection: $model.tunnelSelection) {
            TableColumn("Status") { row in
                HStack(spacing: 6) {
                    StatusDot(color: row.tint)
                    Text(row.status)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 90, ideal: 130)

            TableColumn("Name") { row in
                Text(row.name)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Address") { row in
                Text(row.address)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 140, ideal: 260)

            TableColumn("Type") { row in
                Text(row.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: ItemID.self) { ids in
            if ids.count == 1, let id = ids.first {
                TunnelActions(id: id)
            }
        } primaryAction: { _ in
            model.inspectorVisible = true
        }
        .overlay {
            if !tunnels.isInstalled {
                ContentUnavailableView {
                    Label("cloudflared Isn't Installed", systemImage: "cloud")
                } description: {
                    Text("Share local ports on a public URL and run your named tunnels with Cloudflare.")
                } actions: {
                    ToolInstallButton(tool: .cloudflared)
                }
            } else if rows.isEmpty, !query.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if rows.isEmpty, tunnels.isDiscovering {
                ProgressView()
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Tunnels", systemImage: "cloud")
                } description: {
                    Text(tunnels.isLoggedIn
                        ? "Share a port from its menu for a quick trycloudflare.com URL, or create a named tunnel with cloudflared tunnel create."
                        : "Share a port from its menu for a quick trycloudflare.com URL. Sign in with cloudflared tunnel login to see your named tunnels.")
                } actions: {
                    if !tunnels.isLoggedIn {
                        Button("Copy Login Command") { Pasteboard.copy("cloudflared tunnel login") }
                    }
                }
            }
        }
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                TunnelControlButton()
            }
            ToolbarItem {
                Menu {
                    Button("Stop Quick Tunnels", systemImage: "bolt.slash") { tunnels.stopAllQuickTunnels() }
                        .disabled(tunnels.quickTunnels.isEmpty)
                    Button("Stop Named Tunnels", systemImage: "stop") { tunnels.stopAllNamedTunnels() }
                        .disabled(tunnels.runningNamedCount == 0)
                    Divider()
                    Toggle("Show Tunnels Managed Elsewhere", isOn: $showManagedElsewhere)
                    Button("Look for Tunnels Again", systemImage: "arrow.clockwise") {
                        tunnels.recheckInstallation()
                        tunnels.discover()
                    }
                    .disabled(tunnels.isDiscovering)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .help("Stop or look for tunnels")
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

private struct TunnelRow: Identifiable {
    var id: ItemID
    var name: String
    var address: String
    var status: String
    var kind: String
    var tint: Color

    init(_ tunnel: QuickTunnel) {
        id = .quickTunnel(tunnel.id)
        name = "Port \(tunnel.port)"
        address = tunnel.host ?? tunnel.lastError ?? ""
        status = tunnel.status.title
        kind = "Quick"
        tint = tunnel.status.tint
    }

    init(_ tunnel: NamedTunnel) {
        id = .namedTunnel(tunnel.id)
        name = tunnel.name
        address = tunnel.publicURLs.first.map { tunnel.publicURLs.count > 1 ? "\($0) +\(tunnel.publicURLs.count - 1)" : $0 } ?? ""
        status = tunnel.statusTitle
        kind = "Named"
        tint = tunnel.tint
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [name, address].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct TunnelControlButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tunnels = model.tunnels
        let quick = tunnels.quickTunnels.filter { model.tunnelSelection.contains(.quickTunnel($0.id)) }
        let named = tunnels.namedTunnels.filter { model.tunnelSelection.contains(.namedTunnel($0.id)) }
        let canRun = quick.isEmpty && !named.isEmpty && named.allSatisfy { !$0.isRunningHere }
        Button(canRun ? "Run" : "Stop", systemImage: canRun ? "play.fill" : "stop.fill") {
            if canRun {
                named.forEach { tunnels.run($0) }
            } else {
                quick.forEach(tunnels.stopQuickTunnel)
                named.forEach(tunnels.stop)
            }
        }
        .disabled(quick.isEmpty && named.isEmpty || canRun && !tunnels.isInstalled)
        .help(canRun ? "Run the selected tunnels" : "Stop the selected tunnels")
    }
}

private struct TunnelActions: View {
    @Environment(AppModel.self) private var model
    let id: ItemID

    var body: some View {
        switch id {
        case .quickTunnel(let tunnelID):
            if let tunnel = model.tunnels.quickTunnels.first(where: { $0.id == tunnelID }) {
                if let url = tunnel.url {
                    URLActions(url: url)
                    Divider()
                }
                Button("Stop Tunnel", systemImage: "stop", role: .destructive) { model.tunnels.stopQuickTunnel(tunnel) }
            }
        case .namedTunnel(let tunnelID):
            if let tunnel = model.tunnels.namedTunnels.first(where: { $0.id == tunnelID }) {
                if tunnel.isRunningHere {
                    Button("Stop Tunnel", systemImage: "stop", role: .destructive) { model.tunnels.stop(tunnel) }
                } else if tunnel.runSafety == .managedElsewhere {
                    Button("Run Anyway", systemImage: "play") { model.tunnels.run(tunnel, allowManagedElsewhere: true) }
                } else {
                    Button("Run Tunnel", systemImage: "play") { model.tunnels.run(tunnel) }
                }
                Divider()
                Button("Copy Tunnel ID", systemImage: "doc.on.doc") { Pasteboard.copy(tunnel.id) }
            }
        default:
            EmptyView()
        }
    }
}
