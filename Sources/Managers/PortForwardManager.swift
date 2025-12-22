import Foundation

// NOTE: Port forward settings (autoStart, showNotifications) are now stored in Rust config
// See: ~/.portkiller/config.json
// Access via: scanner.getSettingsPortForwardAutoStart(), scanner.getSettingsPortForwardShowNotifications()

// MARK: - Port Forward Manager

@Observable
@MainActor
final class PortForwardManager {
    var connections: [PortForwardConnectionState] = []
    var isMonitoring = false

    private var monitorTimer: Timer?
    private let scanner: RustPortScanner

    var allConnected: Bool {
        guard !connections.isEmpty else { return false }
        return connections.allSatisfy(\.isFullyConnected)
    }

    var connectedCount: Int {
        connections.filter(\.isFullyConnected).count
    }

    init(scanner: RustPortScanner) {
        self.scanner = scanner
        loadConnections()
    }

    // MARK: - Load from Rust

    func loadConnections() {
        let configs = scanner.getPortForwardConnections()
        connections = configs.map { PortForwardConnectionState(config: $0) }
        syncStatesFromRust()
    }

    /// Sync runtime states from Rust backend (only updates if changed to reduce @Observable overhead)
    func syncStatesFromRust() {
        let rustStates = scanner.getPortForwardStates()
        for rustState in rustStates {
            // Case-insensitive comparison: Swift UUID is uppercase, Rust is lowercase
            guard let connection = connections.first(where: { $0.id.uuidString.lowercased() == rustState.id.lowercased() }) else {
                continue
            }
            // Only update if values changed (reduces @Observable notifications)
            let newPortForwardStatus = PortForwardStatus.fromRust(rustState.portForwardStatus)
            let newProxyStatus = PortForwardStatus.fromRust(rustState.proxyStatus)

            if connection.portForwardStatus != newPortForwardStatus {
                connection.portForwardStatus = newPortForwardStatus
            }
            if connection.proxyStatus != newProxyStatus {
                connection.proxyStatus = newProxyStatus
            }
            if connection.lastError != rustState.lastError {
                connection.lastError = rustState.lastError
            }
            if connection.isIntentionallyStopped != rustState.isIntentionallyStopped {
                connection.isIntentionallyStopped = rustState.isIntentionallyStopped
            }
        }
    }

    // MARK: - Connection CRUD

    func addConnection(_ config: PortForwardConnectionConfig) {
        // Add to Rust first (synchronous - just file I/O, should be fast)
        do {
            try scanner.addPortForwardConnection(config)
            connections.append(PortForwardConnectionState(config: config))
            print("[PortForward] Added connection: \(config.name)")
        } catch {
            print("[PortForward] Failed to add connection: \(error)")
        }
    }

    func removeConnection(_ id: UUID) {
        stopConnection(id)
        connections.removeAll { $0.id == id }

        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            do {
                try scanner.removePortForwardConnection(id: id)
            } catch {
                print("Failed to remove connection: \(error)")
            }
        }
    }

    func updateConnection(_ config: PortForwardConnectionConfig) {
        guard let connection = connections.first(where: { $0.id == config.id }) else { return }
        let wasConnected = connection.isFullyConnected

        if wasConnected {
            stopConnection(config.id)
        }

        connection.config = config

        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            do {
                try scanner.updatePortForwardConnection(config)
            } catch {
                print("Failed to update connection: \(error)")
            }
        }

        if wasConnected && config.isEnabled {
            startConnection(config.id)
        }
    }

    // MARK: - Bulk Operations

    func startAll() {
        print("[PortForward] startAll called, connections count: \(connections.count)")
        for connection in connections where connection.config.isEnabled {
            print("[PortForward] Auto-starting: \(connection.config.name)")
            startConnection(connection.id)
        }
    }

    func stopAll() {
        stopMonitoring()
        for connection in connections {
            connection.portForwardStatus = .disconnected
            connection.proxyStatus = .disconnected
            connection.isIntentionallyStopped = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            do {
                try scanner.stopAllPortForwards()
            } catch {
                print("Failed to stop all: \(error)")
            }
        }
    }

    // MARK: - Single Connection Operations

    func startConnection(_ id: UUID) {
        guard let connection = connections.first(where: { $0.id == id }) else {
            print("[PortForward] Connection not found: \(id)")
            return
        }

        print("[PortForward] Starting connection: \(connection.config.name) (\(id))")

        connection.isIntentionallyStopped = false
        connection.portForwardStatus = .connecting

        // Start monitoring if not already running
        startMonitoring()

        // Run on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            print("[PortForward] Calling Rust startPortForward...")
            do {
                try scanner.startPortForward(id: id)
                print("[PortForward] Rust startPortForward completed successfully")
            } catch {
                print("[PortForward] Rust startPortForward failed: \(error)")
                DispatchQueue.main.async {
                    connection.portForwardStatus = .error
                    connection.lastError = error.localizedDescription
                }
            }
        }
    }

    func stopConnection(_ id: UUID) {
        guard let connection = connections.first(where: { $0.id == id }) else { return }

        connection.isIntentionallyStopped = true
        connection.portForwardStatus = .disconnected
        connection.proxyStatus = .disconnected

        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            do {
                try scanner.stopPortForward(id: id)
            } catch {
                print("Failed to stop connection: \(error)")
            }
        }
    }

    func restartConnection(_ id: UUID) {
        guard let connection = connections.first(where: { $0.id == id }) else { return }

        connection.portForwardStatus = .connecting
        connection.isIntentionallyStopped = false

        startMonitoring()

        DispatchQueue.global(qos: .userInitiated).async { [scanner] in
            do {
                try scanner.restartPortForward(id: id)
            } catch {
                print("Failed to restart connection: \(error)")
            }
        }
    }

    // MARK: - Monitoring (Timer-based for reliability)

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        print("[PortForward] Starting monitoring...")

        // Use Timer on main thread (3s interval to reduce CPU/memory overhead)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.performMonitoringCycle()
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private func performMonitoringCycle() {
        let scanner = self.scanner

        // Run Rust monitoring on background thread
        DispatchQueue.global(qos: .utility).async {
            scanner.monitorPortForwards()

            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                self?.syncStatesFromRust()
                self?.processNotifications()
            }
        }
    }

    // MARK: - Notifications

    private func processNotifications() {
        // Check notification setting from Rust config
        guard scanner.getSettingsPortForwardShowNotifications() else { return }

        let notifications = scanner.getPortForwardNotifications()
        for notification in notifications {
            switch notification.notificationType {
            case "connected":
                NotificationService.shared.notify(
                    title: "Port Forward Connected",
                    body: "\(notification.connectionName) is now connected"
                )
            case "disconnected":
                NotificationService.shared.notify(
                    title: "Port Forward Disconnected",
                    body: "\(notification.connectionName) disconnected"
                )
            case "error":
                NotificationService.shared.notify(
                    title: "Port Forward Error",
                    body: "\(notification.connectionName) encountered an error"
                )
            default:
                break
            }
        }
    }
}
