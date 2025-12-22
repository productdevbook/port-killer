/**
 * WatchedPort.swift
 * PortKiller
 *
 * Represents a port that is being monitored for status changes.
 * Users can configure notifications when a watched port starts or stops.
 */

import Foundation
import Defaults

/// A port being monitored for status changes
///
/// WatchedPort allows users to track specific ports and receive notifications
/// when they become active (a process starts using them) or inactive (the process
/// stops using them). Each watched port can be configured independently for
/// start and stop notifications.
struct WatchedPort: Identifiable, Codable, Defaults.Serializable, Sendable {
    /// Unique identifier for this watched port
    let id: UUID

    /// The port number being watched
    let port: Int

    /// Whether to send a notification when this port becomes active
    var notifyOnStart: Bool

    /// Whether to send a notification when this port becomes inactive
    var notifyOnStop: Bool

    /// Create a new watched port
    ///
    /// - Parameters:
    ///   - port: The port number to watch
    ///   - notifyOnStart: Send notification when port starts (default: true)
    ///   - notifyOnStop: Send notification when port stops (default: true)
    init(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = UUID()
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }

    /// Create a watched port with a specific ID (used for Rust conversion)
    private init(id: UUID, port: Int, notifyOnStart: Bool, notifyOnStop: Bool) {
        self.id = id
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }

    /// Create a WatchedPort from Rust FFI RustWatchedPort
    ///
    /// - Parameter rustPort: The UniFFI-generated RustWatchedPort from Rust
    /// - Returns: A Swift WatchedPort instance, or nil if ID parsing fails
    static func fromRust(_ rustPort: RustWatchedPort) -> WatchedPort? {
        guard let id = UUID(uuidString: rustPort.id) else {
            return nil
        }
        return WatchedPort(
            id: id,
            port: Int(rustPort.port),
            notifyOnStart: rustPort.notifyOnStart,
            notifyOnStop: rustPort.notifyOnStop
        )
    }
}
