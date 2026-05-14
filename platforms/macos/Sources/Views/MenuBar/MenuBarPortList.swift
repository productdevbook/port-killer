/// MenuBarPortList - Scrollable port list container
///
/// Manages the display of ports in either list or tree view mode.
/// Shows an empty state when no ports are found.
/// Includes Kubernetes port-forward connections at the top.
///
/// - Note: Uses LazyVStack for performance with large port lists.
/// - Important: Tree view groups ports by process, list view shows flat list.

import SwiftUI

struct MenuBarPortList: View {
    let filteredPorts: [PortInfo]
    let filteredPortForwardConnections: [PortForwardConnectionState]
    let groupedByProcess: [ProcessGroup]
    let useTreeView: Bool
    @Binding var expandedProcesses: Set<String>
    @Binding var confirmingKillPort: String?
    @Bindable var state: AppState

    /// Named tunnels worth showing in the menu bar: currently running + any with
    /// local ingress (the ones the user likely wants quick access to). Filters out
    /// dashboard-managed prod tunnels to avoid clutter.
    private var menuBarNamedTunnels: [NamedCloudflareTunnel] {
        state.namedTunnelManager.tunnels.filter { tunnel in
            tunnel.status == .running ||
            tunnel.status == .starting ||
            tunnel.runSafety == .safe
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Local ports first — port killing is the app's primary job, so this
                // is where the user's eye should land. Networking sections live below.
                if filteredPorts.isEmpty && filteredPortForwardConnections.isEmpty && state.tunnelManager.tunnels.isEmpty && menuBarNamedTunnels.isEmpty {
                    emptyState
                } else if !filteredPorts.isEmpty {
                    sectionHeader("Local Ports", icon: "network", color: .green)

                    if useTreeView {
                        treeView
                    } else {
                        listView
                    }
                }

                // K8s Port Forward connections grouped by namespace
                if !filteredPortForwardConnections.isEmpty {
                    sectionHeader("K8s Port Forward", icon: "point.3.connected.trianglepath.dotted", color: .blue)

                    ForEach(connectionsByNamespace, id: \.namespace) { group in
                        namespaceHeader(group.namespace, count: group.connections.count)
                        ForEach(group.connections) { connection in
                            MenuBarPortForwardRow(connection: connection, state: state)
                        }
                    }
                }

                // Active Quick Tunnels (port-derived)
                if !state.tunnelManager.tunnels.isEmpty {
                    sectionHeader("Quick Tunnels", icon: "bolt.fill", color: .yellow)

                    ForEach(state.tunnelManager.tunnels) { tunnel in
                        MenuBarTunnelRow(tunnel: tunnel, state: state)
                    }
                }

                // Named (persistent) Cloudflare Tunnels — at the bottom: a tunnel
                // runner is the least-frequent quick action versus inspecting/killing ports.
                if !menuBarNamedTunnels.isEmpty {
                    sectionHeader("My Tunnels", icon: "cloud.fill", color: .orange)

                    ForEach(menuBarNamedTunnels) { tunnel in
                        MenuBarNamedTunnelRow(tunnel: tunnel, state: state)
                    }
                }
            }
        }
        .frame(height: 400)
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private var connectionsByNamespace: [(namespace: String, connections: [PortForwardConnectionState])] {
        let grouped = Dictionary(grouping: filteredPortForwardConnections) { $0.config.namespace }
        return grouped.map { (namespace: $0.key, connections: $0.value) }
            .sorted { $0.namespace < $1.namespace }
    }

    private func namespaceHeader(_ namespace: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(namespace)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    /// Empty state shown when no ports are found
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "network.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No open ports")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Tree view groups ports by process
    private var treeView: some View {
        ForEach(groupedByProcess) { group in
            MenuBarProcessGroupRow(
                group: group,
                isExpanded: expandedProcesses.contains(group.id),
                onToggleExpand: {
                    if expandedProcesses.contains(group.id) {
                        expandedProcesses.remove(group.id)
                    } else {
                        expandedProcesses.insert(group.id)
                    }
                },
                onKillProcess: {
                    for port in group.ports {
                        Task { await state.killPort(port) }
                    }
                },
                state: state
            )
        }
    }

    /// List view shows flat list of ports
    private var listView: some View {
        ForEach(filteredPorts) { port in
            MenuBarPortRow(port: port, state: state, confirmingKill: $confirmingKillPort)
        }
    }
}
