/**
 * ProcessGroup.swift
 * PortKiller
 *
 * Groups multiple ports owned by the same process together.
 * Used in tree view mode to display processes and their ports hierarchically.
 */

import Foundation

/// A collection of ports owned by the same process
///
/// ProcessGroup is used in tree view mode to organize multiple ports under
/// their owning process. This provides a hierarchical view where users can
/// expand/collapse processes to see all their associated ports.
struct ProcessGroup: Identifiable, Sendable {
    /// Process name - used as stable identifier for grouping
    let id: String

    /// Name of the process owning these ports
    let processName: String

    /// All PIDs in this group
    let pids: [Int]

    /// All ports owned by this process (across all PIDs)
    let ports: [PortInfo]
}
