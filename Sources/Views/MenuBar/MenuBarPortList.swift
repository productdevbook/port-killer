/// MenuBarPortList - Scrollable port list container
///
/// Manages the display of ports in either list or tree view mode.
/// Shows an empty state when no ports are found.
///
/// - Note: Uses LazyVStack for performance with large port lists.
/// - Important: Tree view groups ports by process, list view shows flat list.

import SwiftUI

struct MenuBarPortList: View {
    let filteredPorts: [PortInfo]
    let groupedByProcess: [ProcessGroup]
    let useTreeView: Bool
    @Binding var expandedProcesses: Set<Int>
    @Binding var confirmingKillPort: UUID?
    @Bindable var state: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredPorts.isEmpty {
                    emptyState
                } else if useTreeView {
                    treeView
                } else {
                    listView
                }
            }
        }
        .frame(height: 400)
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
