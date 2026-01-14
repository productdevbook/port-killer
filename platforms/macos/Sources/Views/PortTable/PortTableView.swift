/// PortTableView - Main port table display
///
/// Displays ports in a sortable table format with support for:
/// - List view (flat list of all ports)
/// - Tree view (grouped by process)
/// - Column sorting (port, process, PID, type, address, user, actions)
/// - Empty state when no ports are found
///
/// - Note: Uses LazyVStack for performance with large port lists.
/// - Important: Integrates with AppState for port management.

import SwiftUI
import Defaults

struct PortTableView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .port
    @State private var sortAscending = true
    @Default(.useTreeView) private var useTreeView
    @State private var expandedProcesses: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerRow

            Divider()

            // Port List
            if appState.filteredPorts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if useTreeView {
                            treeView
                        } else {
                            listView
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    useTreeView.toggle()
                } label: {
                    Label(useTreeView ? "List View" : "Tree View", systemImage: useTreeView ? "list.bullet" : "list.bullet.indent")
                }
                .help(useTreeView ? "Switch to List View" : "Switch to Tree View")
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Favorite header (centered)
            Button {
                if sortOrder == .actions {
                    sortAscending.toggle()
                } else {
                    sortOrder = .actions
                    sortAscending = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("★")
                        .font(.caption.weight(.medium))
                    if sortOrder == .actions {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(sortOrder == .actions ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 40, alignment: .center)

            // Account for status indicator circle space
            Spacer()
                .frame(width: 16)
            headerButton("Port", .port, width: 70)
            // Process column (flexible)
            Button {
                if sortOrder == .process {
                    sortAscending.toggle()
                } else {
                    sortOrder = .process
                    sortAscending = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Process")
                        .font(.caption.weight(.medium))
                    if sortOrder == .process {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(sortOrder == .process ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            headerButton("PID", .pid, width: 70)
            headerButton("Type", .type, width: 100)
            headerButton("Address", .address, width: 80)
            headerButton("User", .user, width: 70)
            Spacer()
            Text("Actions")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Creates a sortable header button
    private func headerButton(_ title: String, _ order: SortOrder, width: CGFloat) -> some View {
        Button {
            if sortOrder == order {
                sortAscending.toggle()
            } else {
                sortOrder = order
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                if sortOrder == order {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundStyle(sortOrder == order ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Ports", systemImage: "network.slash")
        } description: {
            Text("No listening ports found")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - View Modes

    /// Tree view groups ports by process
    private var treeView: some View {
        ForEach(groupedPorts) { group in
            ProcessGroupListRow(
                group: group,
                isExpanded: expandedProcesses.contains(group.id),
                onToggleExpand: {
                    if expandedProcesses.contains(group.id) {
                        expandedProcesses.remove(group.id)
                    } else {
                        expandedProcesses.insert(group.id)
                    }
                }
            )

            if expandedProcesses.contains(group.id) {
                ForEach(group.ports) { port in
                    NestedPortListRow(port: port)
                        .background(appState.selectedPortID == port.id ? Color.accentColor.opacity(0.2) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedPortID = port.id
                        }
                }
            }
        }
    }

    /// List view shows flat list of ports
    private var listView: some View {
        ForEach(sortedPorts) { port in
            PortListRow(port: port)
                .background(appState.selectedPortID == port.id ? Color.accentColor.opacity(0.2) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.selectedPortID = port.id
                }
        }
    }

    // MARK: - Data Processing

    /// Groups ports by process for tree view
    private var groupedPorts: [ProcessGroup] {
        let grouped = Dictionary(grouping: appState.filteredPorts) { $0.pid }
        return grouped.map { pid, ports in
            ProcessGroup(
                id: pid,
                processName: ports.first?.processName ?? "Unknown",
                ports: ports.sorted { $0.port < $1.port }
            )
        }.sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }

    /// Sorts ports based on current sort order
    private var sortedPorts: [PortInfo] {
        let ports = appState.filteredPorts
        return ports.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .port:
                result = a.port < b.port
            case .process:
                result = a.processName.localizedCaseInsensitiveCompare(b.processName) == .orderedAscending
            case .pid:
                result = a.pid < b.pid
            case .type:
                result = a.processType.rawValue < b.processType.rawValue
            case .address:
                result = a.address.localizedCaseInsensitiveCompare(b.address) == .orderedAscending
            case .user:
                result = a.user.localizedCaseInsensitiveCompare(b.user) == .orderedAscending
            case .actions:
                // Sort by favorite/watched status
                let aIsFavorite = appState.isFavorite(a.port)
                let aIsWatching = appState.isWatching(a.port)
                let bIsFavorite = appState.isFavorite(b.port)
                let bIsWatching = appState.isWatching(b.port)

                // Priority: Favorite > Watching > Neither
                let aPriority = aIsFavorite ? 2 : (aIsWatching ? 1 : 0)
                let bPriority = bIsFavorite ? 2 : (bIsWatching ? 1 : 0)

                if aPriority != bPriority {
                    result = aPriority > bPriority
                } else {
                    // Same priority, sort by port number
                    result = a.port < b.port
                }
            }
            return sortAscending ? result : !result
        }
    }
}
