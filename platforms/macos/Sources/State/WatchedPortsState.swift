/**
 * WatchedPortsState.swift
 * PortKiller
 *
 * Manages watched ports state with persistence and notifications.
 * Extracted from AppState for single responsibility.
 */

import Foundation

/// Manages watched ports and notifications
@Observable
@MainActor
final class WatchedPortsState {
    /// Storage backend for persistence
    private let storage: WatchedPortsStorageProtocol

    /// Notification service for alerts
    private let notificationService: NotificationServiceProtocol

    /// Cached watched ports, synced with storage on change
    private var _watchedPorts: [WatchedPort] {
        didSet {
            storage.save(_watchedPorts)
        }
    }

    /// Tracks previous port states for change detection.
    /// Written on every scan and never displayed, so not observed.
    @ObservationIgnored var previousPortStates: [Int: Bool] = [:]

    /// Ports being watched for state changes
    var watchedPorts: [WatchedPort] {
        get { _watchedPorts }
        set { _watchedPorts = newValue }
    }

    /// Initialize with storage and notification backends
    init(
        storage: WatchedPortsStorageProtocol = DefaultsWatchedPortsStorage(),
        notificationService: NotificationServiceProtocol = NotificationService.shared
    ) {
        self.storage = storage
        self.notificationService = notificationService
        self._watchedPorts = storage.load()
    }

    /// Toggles watch status for a port
    /// - Parameter port: Port number to toggle
    func toggle(_ port: Int) {
        if let idx = _watchedPorts.firstIndex(where: { $0.port == port }) {
            previousPortStates.removeValue(forKey: port)
            _watchedPorts.remove(at: idx)
        } else {
            _watchedPorts.append(WatchedPort(port: port))
        }
    }

    /// Checks if a port is being watched
    /// - Parameter port: Port number to check
    /// - Returns: True if the port is being watched
    func isWatching(_ port: Int) -> Bool {
        _watchedPorts.contains { $0.port == port }
    }

    /// Updates notification preferences for a watched port
    func updateWatch(_ port: Int, onStart: Bool, onStop: Bool) {
        if let idx = _watchedPorts.firstIndex(where: { $0.port == port }) {
            _watchedPorts[idx].notifyOnStart = onStart
            _watchedPorts[idx].notifyOnStop = onStop
        }
    }

    /// Removes a watched port by its ID
    func removeWatch(_ id: UUID) {
        if let w = _watchedPorts.first(where: { $0.id == id }) {
            previousPortStates.removeValue(forKey: w.port)
        }
        _watchedPorts.removeAll { $0.id == id }
    }

    /// Checks watched ports for state changes and triggers notifications
    /// - Parameter ports: Current active ports to check against
    func checkForChanges(ports: [PortInfo]) {
        let activePorts = Set(ports.map { $0.port })

        for w in _watchedPorts {
            let isActive = activePorts.contains(w.port)

            if let wasActive = previousPortStates[w.port] {
                if wasActive && !isActive && w.notifyOnStop {
                    notificationService.notify(
                        title: "Port \(w.port) Available",
                        body: "Port is now free."
                    )
                } else if !wasActive && isActive && w.notifyOnStart {
                    let name = ports.first { $0.port == w.port }?.processName ?? "Unknown"
                    notificationService.notify(
                        title: "Port \(w.port) In Use",
                        body: "Used by \(name)."
                    )
                }
            }

            previousPortStates[w.port] = isActive
        }
    }
}
