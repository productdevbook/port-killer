import Foundation

extension AppState {
    /// Refreshes the port list by scanning for active ports using the Rust backend.
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let scanned = await scanner.scanPorts()
        updatePorts(scanned)
        checkWatchedPorts()
    }

    /// Updates the internal port list only if there are changes.
    func updatePorts(_ newPorts: [PortInfo]) {
        let newSet = Set(newPorts.map { "\($0.port)-\($0.pid)" })
        let oldSet = Set(ports.map { "\($0.port)-\($0.pid)" })
        guard newSet != oldSet else { return }

        ports = newPorts.sorted { a, b in
            let aFav = favorites.contains(a.port)
            let bFav = favorites.contains(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }
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
