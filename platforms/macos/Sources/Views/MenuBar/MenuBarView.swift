/// MenuBarView - Main menu bar dropdown interface
///
/// Displays the list of active ports in a compact menu bar dropdown.
/// Supports both list and tree view modes for port organization.
///
/// - Note: This view is shown when clicking the menu bar icon.
/// - Important: Uses `@Bindable var state: AppState` for state management.

import SwiftUI
import Defaults

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var state: AppState
    @State private var searchText = ""
    @State private var confirmingKillAll = false
    @State private var confirmingKillPort: String?
    @State private var hoveredPort: String?
    @State private var expandedProcesses: Set<Int> = []
    @Default(.useTreeView) private var useTreeView
    @Default(.hideSystemProcesses) private var hideSystemProcesses

    // MARK: - Cached Data (Memory Optimization)
    @State private var cachedFilteredPorts: [PortInfo] = []
    @State private var cachedGroups: [ProcessGroup] = []
    @State private var lastCacheKey: CacheKey?

    /// Cache key to detect when recalculation is needed
    private struct CacheKey: Equatable {
        let portsCount: Int
        let firstPortHash: Int
        let searchText: String
        let hideSystem: Bool
    }

    private var groupedByProcess: [ProcessGroup] { cachedGroups }

    /// Updates all cached data only when inputs change
    private func updateCachedData() {
        let currentKey = CacheKey(
            portsCount: state.ports.count,
            firstPortHash: state.ports.first?.hashValue ?? 0,
            searchText: searchText,
            hideSystem: hideSystemProcesses
        )

        // Skip if nothing changed
        guard currentKey != lastCacheKey else { return }
        lastCacheKey = currentKey

        // Compute filtered ports once
        var filtered: [PortInfo]
        if searchText.isEmpty {
            filtered = state.ports
        } else {
            filtered = state.ports.filter {
                String($0.port).contains(searchText) || $0.processName.localizedCaseInsensitiveContains(searchText)
            }
        }

        if hideSystemProcesses {
            filtered = filtered.filter { $0.processType != .system }
        }

        cachedFilteredPorts = filtered.sorted { a, b in
            let aFav = state.isFavorite(a.port)
            let bFav = state.isFavorite(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }

        // Compute groups from cached filtered ports
        let grouped = Dictionary(grouping: cachedFilteredPorts) { $0.pid }
        cachedGroups = grouped.map { pid, ports in
            ProcessGroup(
                id: pid,
                processName: ports.first?.processName ?? "Unknown",
                ports: ports.sorted { $0.port < $1.port }
            )
        }.sorted { a, b in
            let aHasFavorite = a.ports.contains(where: { state.isFavorite($0.port) })
            let aHasWatched = a.ports.contains(where: { state.isWatching($0.port) })
            let bHasFavorite = b.ports.contains(where: { state.isFavorite($0.port) })
            let bHasWatched = b.ports.contains(where: { state.isWatching($0.port) })

            let aPriority = aHasFavorite ? 2 : (aHasWatched ? 1 : 0)
            let bPriority = bHasFavorite ? 2 : (bHasWatched ? 1 : 0)

            if aPriority != bPriority {
                return aPriority > bPriority
            } else {
                return a.processName.localizedCaseInsensitiveCompare(b.processName) == .orderedAscending
            }
        }

        // Keep expansion state bounded to currently visible process IDs.
        let visibleProcessIDs = Set(cachedGroups.map(\.id))
        expandedProcesses = expandedProcesses.intersection(visibleProcessIDs)
    }

    /// Cached filtered ports (no allocation on access)
    private var filteredPorts: [PortInfo] { cachedFilteredPorts }

    /// Filters port-forward connections based on search text
    private var filteredPortForwardConnections: [PortForwardConnectionState] {
        let connections = state.portForwardManager.connections
        if searchText.isEmpty { return connections }
        return connections.filter {
            String($0.effectivePort).contains(searchText) ||
            $0.config.name.localizedCaseInsensitiveContains(searchText) ||
            $0.config.namespace.localizedCaseInsensitiveContains(searchText) ||
            $0.config.service.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeader(searchText: $searchText, portCount: filteredPorts.count + filteredPortForwardConnections.count)

            Divider()

            MenuBarPortList(
                filteredPorts: filteredPorts,
                filteredPortForwardConnections: filteredPortForwardConnections,
                groupedByProcess: groupedByProcess,
                useTreeView: useTreeView,
                expandedProcesses: $expandedProcesses,
                confirmingKillPort: $confirmingKillPort,
                state: state
            )

            Divider()

            MenuBarActions(
                confirmingKillAll: $confirmingKillAll,
                useTreeView: $useTreeView,
                state: state,
                openWindow: openWindow
            )
        }
        .frame(width: 340)
        .onAppear { updateCachedData() }
        .onChange(of: state.ports) { _, _ in updateCachedData() }
        .onChange(of: searchText) { _, _ in updateCachedData() }
        .onChange(of: hideSystemProcesses) { _, _ in updateCachedData() }
    }
}
