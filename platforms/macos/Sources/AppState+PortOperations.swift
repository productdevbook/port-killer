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
            let didChange = updatePorts(scanned)
            didChangeAny = didChangeAny || didChange

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
            ports.removeAll { $0.id == port.id }
            await refresh()
        }
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
