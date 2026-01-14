/**
 * PortInfo.swift
 * PortKiller
 *
 * Represents information about a network port and its associated process.
 * Each PortInfo instance contains details about a port's number, process ID,
 * process name, network address, and user ownership.
 */

import Foundation

/// Information about a network port and its associated process
///
/// PortInfo encapsulates all details about a listening network port, including
/// the process that owns it, the address it's bound to, and whether it's currently active.
struct PortInfo: Identifiable, Hashable, Sendable {
    /// Unique identifier for this port info instance
    let id = UUID()

    /// The port number (e.g., 3000, 8080)
    let port: Int

    /// Process ID of the process using this port
    let pid: Int

    /// Name of the process using this port
    let processName: String

    /// Network address the port is bound to (e.g., "*:3000", "127.0.0.1:8080")
    let address: String

    /// Username of the process owner
    let user: String

    /// Full command line that started the process
    let command: String

    /// File descriptor information from lsof
    let fd: String

    /// Whether this port is currently active/listening
    let isActive: Bool

    /// Formatted port number for display (e.g., ":3000")
    var displayPort: String { ":\(port)" }

    /// Detected process type based on the process name
    var processType: ProcessType {
        ProcessType.detect(from: processName)
    }

    /// Create an inactive placeholder for a favorited/watched port
    ///
    /// - Parameter port: The port number
    /// - Returns: An inactive PortInfo instance with placeholder values
    static func inactive(port: Int) -> PortInfo {
        PortInfo(
            port: port,
            pid: 0,
            processName: "Not running",
            address: "-",
            user: "-",
            command: "",
            fd: "",
            isActive: false
        )
    }

    /// Create an active port from scan results
    ///
    /// - Parameters:
    ///   - port: The port number
    ///   - pid: Process ID
    ///   - processName: Name of the process
    ///   - address: Network address
    ///   - user: Username of the process owner
    ///   - command: Full command line
    ///   - fd: File descriptor information
    /// - Returns: An active PortInfo instance
    static func active(port: Int, pid: Int, processName: String, address: String, user: String, command: String, fd: String) -> PortInfo {
        PortInfo(
            port: port,
            pid: pid,
            processName: processName,
            address: address,
            user: user,
            command: command,
            fd: fd,
            isActive: true
        )
    }
}
