import Foundation

extension AppState {
    /// Refreshes the port list by scanning for active ports.
    @discardableResult
    func refresh() async -> Bool {
        if isScanning {
            hasPendingRefreshRequest = true
            return false
        }

        var didChangeAny = false

        repeat {
            hasPendingRefreshRequest = false
            isScanning = true

            let scanned = await scanner.scanPorts()
            let previousPorts = ports
            let didChange = updatePorts(scanned)
            didChangeAny = didChangeAny || didChange

            // Check process type notifications for newly appeared ports
            if didChange {
                checkProcessTypeNotifications(oldPorts: previousPorts, newPorts: scanned)
                WebhookService.shared.checkPortChanges(oldPorts: previousPorts, newPorts: scanned)
            }

            // Always update watcher state to keep transition baseline accurate.
            checkWatchedPorts()
            isScanning = false
        } while hasPendingRefreshRequest

        return didChangeAny
    }

    /// Updates the internal port list only if there are changes.
    @discardableResult
    func updatePorts(_ newPorts: [PortInfo]) -> Bool {
        let newSet = Set(newPorts.map { "\($0.port)-\($0.pid)" })
        let oldSet = Set(ports.map { "\($0.port)-\($0.pid)" })
        guard newSet != oldSet else { return false }

        ports = newPorts.sorted { a, b in
            let aFav = favorites.contains(a.port)
            let bFav = favorites.contains(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }
        return true
    }

    /// Kills the process using the specified port.
    func killPort(_ port: PortInfo) async {
        if await scanner.killProcessGracefully(pid: port.pid) {
            WebhookService.shared.send(event: .portKilled, port: port)
            ports.removeAll { $0.id == port.id }
            await refresh()
        }
    }

    /// Kills the listening process and all processes with ESTABLISHED connections to the port.
    func killPortDeep(_ port: PortInfo) async {
        // 1. Kill the listener
        let killed = await scanner.killProcessGracefully(pid: port.pid)
        if killed {
            WebhookService.shared.send(event: .portKilled, port: port)
        }

        // 2. Find and kill ESTABLISHED connections
        let establishedPids = await scanner.findEstablishedPids(for: port.port)
        for pid in establishedPids where pid != port.pid {
            _ = await scanner.killProcessGracefully(pid: pid)
        }

        ports.removeAll { $0.id == port.id }
        await refresh()
    }

    /// Kills all processes currently using ports.
    func killAll() async {
        for port in ports {
            _ = await scanner.killProcessGracefully(pid: port.pid)
        }
        ports.removeAll()
        await refresh()
    }
}
