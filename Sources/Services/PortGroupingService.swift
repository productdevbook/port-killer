/**
 * PortGroupingService.swift
 * PortKiller
 *
 * Centralized service for grouping ports by process or type.
 * Extracts duplicate grouping logic from views into a reusable service.
 */

import Foundation

/// Service for grouping and organizing port information
///
/// PortGroupingService provides centralized logic for organizing ports
/// in different ways, such as grouping by process (PID) or by process type.
/// This eliminates duplicate grouping logic across multiple views.
actor PortGroupingService {
    /// Singleton instance
    static let shared = PortGroupingService()

    private init() {}

    /// Groups ports by their owning process
    ///
    /// Creates ProcessGroup instances containing all ports owned by the same process.
    /// Groups are sorted alphabetically by process name for consistent display.
    ///
    /// - Parameter ports: Array of ports to group
    /// - Returns: Array of ProcessGroup instances, sorted by process name
    ///
    /// # Example
    /// ```swift
    /// let groups = await PortGroupingService.shared.groupByProcess(ports)
    /// // groups[0] might contain: ProcessGroup(id: 1234, processName: "node", ports: [3000, 3001])
    /// ```
    func groupByProcess(_ ports: [PortInfo]) -> [ProcessGroup] {
        let grouped = Dictionary(grouping: ports) { $0.pid }
        return grouped.map { pid, ports in
            ProcessGroup(
                id: pid,
                processName: ports.first?.processName ?? "Unknown",
                ports: ports.sorted { $0.port < $1.port }
            )
        }.sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }

    /// Groups ports by their owning process with custom sorting
    ///
    /// Creates ProcessGroup instances with custom sort logic that prioritizes
    /// favorited and watched ports. This is used in the menu bar view.
    ///
    /// - Parameters:
    ///   - ports: Array of ports to group
    ///   - favorites: Set of favorited port numbers
    ///   - watched: Set of watched port numbers
    /// - Returns: Array of ProcessGroup instances, sorted by priority then name
    func groupByProcessWithPriority(_ ports: [PortInfo], favorites: Set<Int>, watched: Set<Int>) -> [ProcessGroup] {
        let grouped = Dictionary(grouping: ports) { $0.pid }
        return grouped.map { pid, ports in
            ProcessGroup(
                id: pid,
                processName: ports.first?.processName ?? "Unknown",
                ports: ports.sorted { $0.port < $1.port }
            )
        }.sorted { a, b in
            // Check if groups have favorite or watched ports
            let aHasFavorite = a.ports.contains(where: { favorites.contains($0.port) })
            let aHasWatched = a.ports.contains(where: { watched.contains($0.port) })
            let bHasFavorite = b.ports.contains(where: { favorites.contains($0.port) })
            let bHasWatched = b.ports.contains(where: { watched.contains($0.port) })

            // Priority: Favorite > Watched > Neither
            let aPriority = aHasFavorite ? 2 : (aHasWatched ? 1 : 0)
            let bPriority = bHasFavorite ? 2 : (bHasWatched ? 1 : 0)

            if aPriority != bPriority {
                return aPriority > bPriority
            } else {
                // Same priority, sort alphabetically by process name
                return a.processName.localizedCaseInsensitiveCompare(b.processName) == .orderedAscending
            }
        }
    }

    /// Groups ports by their process type
    ///
    /// Organizes ports into categories based on their detected process type
    /// (web server, database, development tool, system process, or other).
    ///
    /// - Parameter ports: Array of ports to group
    /// - Returns: Dictionary mapping ProcessType to arrays of ports
    ///
    /// # Example
    /// ```swift
    /// let grouped = await PortGroupingService.shared.groupByType(ports)
    /// let webServers = grouped[.webServer] // All ports for web servers
    /// let databases = grouped[.database]   // All ports for databases
    /// ```
    func groupByType(_ ports: [PortInfo]) -> [ProcessType: [PortInfo]] {
        Dictionary(grouping: ports) { $0.processType }
    }
}
