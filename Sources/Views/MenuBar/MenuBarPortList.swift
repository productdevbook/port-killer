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
    @Binding var expandedProcesses: Set<Int>
    @Binding var confirmingKillPort: UUID?
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Active Cloudflare Tunnels
                if !state.tunnelManager.tunnels.isEmpty {
                    sectionHeader("Cloudflare Tunnels", icon: "cloud.fill", color: .orange)

                    ForEach(state.tunnelManager.tunnels) { tunnel in
                        MenuBarTunnelRow(tunnel: tunnel, state: state)
                    }
                }

                // Port Forward connections
                if !filteredPortForwardConnections.isEmpty {
                    sectionHeader("K8s Port Forward", icon: "point.3.connected.trianglepath.dotted", color: .blue)

                    ForEach(filteredPortForwardConnections) { connection in
                        PortForwardRow(connection: connection, state: state)
                    }
                }

                // Normal ports
                if filteredPorts.isEmpty && filteredPortForwardConnections.isEmpty && state.tunnelManager.tunnels.isEmpty {
                    emptyState
                } else if !filteredPorts.isEmpty {
                    sectionHeader("Local Ports", icon: "network", color: .green)

                    if useTreeView {
                        treeView
                    } else {
                        listView
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
            ProcessGroupRow(
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
            PortRow(port: port, state: state, confirmingKill: $confirmingKillPort)
        }
    }
}
