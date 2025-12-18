import Foundation
import Defaults

// MARK: - Defaults Keys for Port Forwarder

extension Defaults.Keys {
    static let portForwardConnections = Key<[PortForwardConnectionConfig]>("portForwardConnections", default: [])
    static let portForwardAutoStart = Key<Bool>("portForwardAutoStart", default: false)
    static let portForwardShowNotifications = Key<Bool>("portForwardShowNotifications", default: true)
    static let customKubectlPath = Key<String?>("customKubectlPath", default: nil)
    static let customSocatPath = Key<String?>("customSocatPath", default: nil)
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
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        stopConnection(id)
        connections.remove(at: index)
        saveConnections()
    }

    func updateConnection(_ config: PortForwardConnectionConfig) {
        guard let index = connections.firstIndex(where: { $0.id == config.id }) else { return }
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
        guard let state = connections.first(where: { $0.id == id }) else { return }
        let config = state.config

        Task {
            await processManager.setLogHandler(for: id) { [weak state] message, type, isError in
                Task { @MainActor in
                    state?.appendLog(message, type: type, isError: isError)
                }
            }

            await processManager.setPortConflictHandler(for: id) { [weak self, weak state] port in
                Task { @MainActor in
                    guard let self = self, let state = state else { return }
                    state.appendLog("Port \(port) in use, auto-recovering...", type: .portForward, isError: false)

                    await self.processManager.killProcessOnPort(port)

                    try? await Task.sleep(for: .milliseconds(500))

                    state.appendLog("Retrying connection...", type: .portForward, isError: false)
                    self.restartConnection(id)
                }
            }
        }

        state.portForwardStatus = .connecting
        state.portForwardTask = Task {
            await runPortForward(for: state, config: config)
        }
    }

    func stopConnection(_ id: UUID) {
        guard let state = connections.first(where: { $0.id == id }) else { return }

        state.proxyTask?.cancel()
        state.proxyTask = nil
        state.proxyStatus = .disconnected

        state.portForwardTask?.cancel()
        state.portForwardTask = nil
        state.portForwardStatus = .disconnected

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
