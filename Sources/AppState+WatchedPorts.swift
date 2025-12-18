import Foundation

extension AppState {
    /// Toggles watch status for a port.
    func toggleWatch(_ port: Int) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            previousPortStates.removeValue(forKey: port)
            watchedPorts.remove(at: idx)
        } else {
            watchedPorts.append(WatchedPort(port: port))
        }
    }

    /// Checks if a port is being watched.
    func isWatching(_ port: Int) -> Bool { watchedPorts.contains { $0.port == port } }

    /// Updates notification preferences for a watched port.
    func updateWatch(_ port: Int, onStart: Bool, onStop: Bool) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            watchedPorts[idx].notifyOnStart = onStart
            watchedPorts[idx].notifyOnStop = onStop
        }
    }

    /// Removes a watched port by its ID.
    func removeWatch(_ id: UUID) {
        if let w = watchedPorts.first(where: { $0.id == id }) {
            previousPortStates.removeValue(forKey: w.port)
        }
        watchedPorts.removeAll { $0.id == id }
    }

    /// Checks watched ports for state changes and triggers notifications.
    func checkWatchedPorts() {
        let activePorts = Set(ports.map { $0.port })
        for w in watchedPorts {
            let isActive = activePorts.contains(w.port)
            if let wasActive = previousPortStates[w.port] {
                if wasActive && !isActive && w.notifyOnStop {
                    NotificationService.shared.notify(
                        title: "Port \(w.port) Available",
                        body: "Port is now free."
                    )
                } else if !wasActive && isActive && w.notifyOnStart {
                    let name = ports.first { $0.port == w.port }?.processName ?? "Unknown"
                    NotificationService.shared.notify(
                        title: "Port \(w.port) In Use",
                        body: "Used by \(name)."
                    )
                }
            }
            previousPortStates[w.port] = isActive
        }
    }
}
