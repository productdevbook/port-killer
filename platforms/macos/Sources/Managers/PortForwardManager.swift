import Foundation
import Defaults

// MARK: - Defaults Keys for Port Forwarder

extension Defaults.Keys {
    static let portForwardConnections = Key<[PortForwardConnectionConfig]>("portForwardConnections", default: [])
    static let portForwardAutoStart = Key<Bool>("portForwardAutoStart", default: false)
    static let portForwardShowNotifications = Key<Bool>("portForwardShowNotifications", default: true)
    static let customKubectlPath = Key<String?>("customKubectlPath", default: nil)
    static let customSocatPath = Key<String?>("customSocatPath", default: nil)
    static let customCloudflaredPath = Key<String?>("customCloudflaredPath", default: nil)
}

// MARK: - Port Forward Manager

@Observable
@MainActor
final class PortForwardManager {
    var connections: [PortForwardConnectionState] = []
    var isMonitoring = false
    var isKillingProcesses = false

    var monitorTask: Task<Void, Never>?
    let processManager = PortForwardProcessManager()

    var allConnected: Bool {
        guard !connections.isEmpty else { return false }
        return connections.allSatisfy(\.isFullyConnected)
    }

    var connectedCount: Int {
        connections.filter(\.isFullyConnected).count
    }

    // MARK: - Helper Methods

    /// Finds a connection state by its ID
    /// - Parameter id: The UUID of the connection to find
    /// - Returns: The connection state if found, nil otherwise
    func connection(for id: UUID) -> PortForwardConnectionState? {
        connections.first { $0.id == id }
    }

    /// Finds the index of a connection by its ID
    /// - Parameter id: The UUID of the connection to find
    /// - Returns: The index if found, nil otherwise
    func connectionIndex(for id: UUID) -> Int? {
        connections.firstIndex { $0.id == id }
    }

    init() {
        loadConnections()
    }

    // MARK: - Persistence

    func loadConnections() {
        let configs = Defaults[.portForwardConnections]
        connections = configs.map { PortForwardConnectionState(config: $0) }
    }

    func saveConnections() {
        Defaults[.portForwardConnections] = connections.map(\.config)
    }

    // MARK: - Connection CRUD

    func addConnection(_ config: PortForwardConnectionConfig) {
        connections.append(PortForwardConnectionState(config: config))
        saveConnections()
    }

    func removeConnection(_ id: UUID) {
        guard let index = connectionIndex(for: id) else { return }
        stopConnection(id)
        connections.remove(at: index)
        saveConnections()
    }

    func updateConnection(_ config: PortForwardConnectionConfig) {
        guard let index = connectionIndex(for: config.id) else { return }
        let wasConnected = connections[index].isFullyConnected
        if wasConnected {
            stopConnection(config.id)
        }
        connections[index].config = config
        saveConnections()
        if wasConnected && config.isEnabled {
            startConnection(config.id)
        }
    }

    // MARK: - Bulk Operations

    func startAll() {
        for connection in connections where connection.config.isEnabled {
            startConnection(connection.id)
        }
        startMonitoring()
    }

    func stopAll() {
        stopMonitoring()
        for connection in connections {
            stopConnection(connection.id)
        }
    }

    func killStuckProcesses() async {
        isKillingProcesses = true
        stopMonitoring()

        for connection in connections {
            connection.portForwardTask?.cancel()
            connection.proxyTask?.cancel()
            connection.portForwardTask = nil
            connection.proxyTask = nil
        }

        try? await Task.sleep(for: .milliseconds(200))

        await processManager.killAllPortForwarderProcesses()

        for connection in connections {
            connection.portForwardStatus = .disconnected
            connection.proxyStatus = .disconnected
        }

        isKillingProcesses = false
    }

    // MARK: - Single Connection Operations

    func startConnection(_ id: UUID) {
        guard !isKillingProcesses else { return }
        guard let state = connection(for: id) else { return }
        guard state.portForwardTask == nil, state.proxyTask == nil else { return }
        guard state.portForwardStatus != .connecting, state.proxyStatus != .connecting else { return }
        guard !state.isFullyConnected else { return }
        let config = state.config

        // Reset intentional stop flag when starting
        state.isIntentionallyStopped = false

        state.portForwardStatus = .connecting

        // Set up handlers and start port forward in a single task to ensure proper ordering
        state.portForwardTask = Task { [weak self, weak state] in
            guard let self = self, let state = state else { return }

            // Set log handler with proper weak capture (including inner Task)
            let logHandler: LogHandler = { [weak state] message, type, isError in
                guard let state = state else { return }
                Task { @MainActor [weak state] in
                    guard let state = state else { return }
                    state.appendLog(message, type: type, isError: isError)
                }
            }
            await self.processManager.setLogHandler(for: id, handler: logHandler)

            // Set port conflict handler with proper weak capture (including inner Task)
            let conflictHandler: PortConflictHandler = { [weak self, weak state] port in
                guard let self = self, let state = state else { return }
                Task { @MainActor [weak self, weak state] in
                    guard let self = self, let state = state else { return }
                    state.appendLog("Port \(port) in use, auto-recovering...", type: .portForward, isError: false)

                    await self.processManager.killProcessOnPort(port)

                    try? await Task.sleep(for: .milliseconds(500))

                    state.appendLog("Retrying connection...", type: .portForward, isError: false)
                    self.restartConnection(id)
                }
            }
            await self.processManager.setPortConflictHandler(for: id, handler: conflictHandler)

            await self.runPortForward(for: state, config: config)
        }
    }

    func stopConnection(_ id: UUID) {
        guard let state = connection(for: id) else { return }

        // Mark as intentionally stopped to avoid disconnect notification
        state.isIntentionallyStopped = true

        state.proxyTask?.cancel()
        state.proxyTask = nil
        state.proxyStatus = .disconnected

        state.portForwardTask?.cancel()
        state.portForwardTask = nil
        state.portForwardStatus = .disconnected

        // Clear logs to free memory when connection is stopped
        state.clearLogs()

        Task {
            await processManager.killProcesses(for: id)
            await processManager.removeLogHandler(for: id)
            await processManager.removePortConflictHandler(for: id)
        }
    }

    func restartConnection(_ id: UUID) {
        stopConnection(id)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            startConnection(id)
        }
    }
}
