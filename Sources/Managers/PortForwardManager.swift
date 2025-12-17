import Foundation
import Defaults

// MARK: - Defaults Keys for Port Forwarder

extension Defaults.Keys {
    static let portForwardConnections = Key<[PortForwardConnectionConfig]>("portForwardConnections", default: [])
    static let portForwardAutoStart = Key<Bool>("portForwardAutoStart", default: false)
    static let portForwardShowNotifications = Key<Bool>("portForwardShowNotifications", default: true)
}

// MARK: - Port Forward Manager

@Observable
@MainActor
final class PortForwardManager {
    var connections: [PortForwardConnectionState] = []
    var isMonitoring = false
    var isKillingProcesses = false

    private var monitorTask: Task<Void, Never>?
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

        // Cancel all tasks
        for connection in connections {
            connection.portForwardTask?.cancel()
            connection.proxyTask?.cancel()
            connection.portForwardTask = nil
            connection.proxyTask = nil
        }

        try? await Task.sleep(for: .milliseconds(200))

        await processManager.killAllPortForwarderProcesses()

        // Reset all states
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

        // Set up log handler
        Task {
            await processManager.setLogHandler(for: id) { [weak state] message, type, isError in
                Task { @MainActor in
                    state?.appendLog(message, type: type, isError: isError)
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
        }
    }

    func restartConnection(_ id: UUID) {
        stopConnection(id)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            startConnection(id)
        }
    }

    // MARK: - Port Forward Execution

    private func runPortForward(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
        // Direct exec mode: don't use kubectl port-forward, start exec proxy directly
        if config.useDirectExec, config.proxyPort != nil {
            await runDirectExecProxy(for: state, config: config)
            return
        }

        do {
            let process = try await processManager.startPortForward(
                id: state.id,
                namespace: config.namespace,
                service: config.service,
                localPort: config.localPort,
                remotePort: config.remotePort
            )

            try await Task.sleep(for: .seconds(2))

            if process.isRunning {
                state.portForwardStatus = .connected

                if config.proxyPort != nil {
                    state.proxyStatus = .connecting
                    state.proxyTask = Task {
                        await runProxy(for: state, config: config)
                    }
                } else {
                    sendNotificationIfEnabled(title: "Connected", body: "\(config.name) is ready")
                }
            } else {
                state.portForwardStatus = .error
                state.lastError = "Port forward failed to start"
            }
        } catch {
            state.portForwardStatus = .error
            state.lastError = error.localizedDescription
        }
    }

    private func runDirectExecProxy(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
        guard let proxyPort = config.proxyPort else { return }

        state.portForwardStatus = .connected
        state.proxyStatus = .connecting

        do {
            let process = try await processManager.startDirectExecProxy(
                id: state.id,
                namespace: config.namespace,
                service: config.service,
                externalPort: proxyPort,
                remotePort: config.remotePort
            )

            try await Task.sleep(for: .seconds(1))

            if process.isRunning {
                state.proxyStatus = .connected
                sendNotificationIfEnabled(title: "Connected", body: "\(config.name) is ready (multi-connection)")
            } else {
                state.proxyStatus = .error
                state.portForwardStatus = .error
                state.lastError = "Direct exec proxy failed to start"
            }
        } catch {
            state.proxyStatus = .error
            state.portForwardStatus = .error
            state.lastError = error.localizedDescription
        }
    }

    private func runProxy(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
        guard let proxyPort = config.proxyPort else { return }

        do {
            let process = try await processManager.startProxy(
                id: state.id,
                externalPort: proxyPort,
                internalPort: config.localPort
            )

            try await Task.sleep(for: .seconds(1))

            if process.isRunning {
                state.proxyStatus = .connected
                sendNotificationIfEnabled(title: "Connected", body: "\(config.name) is ready")
            } else {
                state.proxyStatus = .error
                state.lastError = "Socat proxy failed to start"
            }
        } catch {
            state.proxyStatus = .error
            state.lastError = error.localizedDescription
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        isMonitoring = true
        monitorTask = Task {
            while !Task.isCancelled && isMonitoring {
                await checkConnections()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func checkConnections() async {
        guard !isKillingProcesses else { return }
        for state in connections {
            guard state.config.isEnabled && state.config.autoReconnect else { continue }

            if state.config.useDirectExec, state.config.proxyPort != nil {
                await checkDirectExecConnection(state)
                continue
            }

            let localPort = state.config.localPort
            let processRunning = await processManager.isProcessRunning(for: state.id, type: .portForward)
            let hasError = await processManager.hasRecentError(for: state.id)
            let pfWorking = await processManager.isPortOpen(port: localPort)

            // Reconnect if disconnected or error
            if state.portForwardStatus == .disconnected || state.portForwardStatus == .error {
                await processManager.clearError(for: state.id)
                startConnection(state.id)
                continue
            }

            // Reconnect on error
            if state.portForwardStatus == .connected && hasError {
                state.lastError = "kubectl error"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                await processManager.killProcesses(for: state.id)
                await processManager.clearError(for: state.id)
                startConnection(state.id)
                continue
            }

            // Reconnect if process died
            if state.portForwardStatus == .connected && !processRunning {
                state.lastError = "Process terminated"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                startConnection(state.id)
                continue
            }

            // Reconnect if port not responding
            if state.portForwardStatus == .connected && !pfWorking {
                state.lastError = "Connection lost"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                await processManager.killProcesses(for: state.id)
                startConnection(state.id)
                continue
            }

            // Check proxy if enabled
            if let proxyPort = state.config.proxyPort {
                if state.proxyStatus == .disconnected && state.portForwardStatus == .connected {
                    state.proxyStatus = .connecting
                    state.proxyTask = Task {
                        await runProxy(for: state, config: state.config)
                    }
                    continue
                }

                let proxyWorking = await processManager.isPortOpen(port: proxyPort)
                if state.proxyStatus == .connected && !proxyWorking {
                    state.proxyStatus = .error
                    state.lastError = "Proxy connection lost"
                    if state.portForwardStatus == .connected {
                        state.proxyStatus = .connecting
                        state.proxyTask = Task {
                            await runProxy(for: state, config: state.config)
                        }
                    }
                }
            }
        }
    }

    private func checkDirectExecConnection(_ state: PortForwardConnectionState) async {
        guard state.config.proxyPort != nil else { return }

        if state.proxyStatus == .connecting {
            return
        }

        let proxyRunning = await processManager.isProcessRunning(for: state.id, type: .proxy)
        let hasError = await processManager.hasRecentError(for: state.id)

        if state.proxyStatus == .disconnected || state.proxyStatus == .error {
            await processManager.clearError(for: state.id)
            startConnection(state.id)
            return
        }

        if state.proxyStatus == .connected && hasError {
            state.lastError = "Proxy error"
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            await processManager.killProcesses(for: state.id)
            await processManager.clearError(for: state.id)
            startConnection(state.id)
            return
        }

        if state.proxyStatus == .connected && !proxyRunning {
            state.lastError = "Proxy terminated"
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            startConnection(state.id)
            return
        }
    }

    // MARK: - Notifications

    private func sendNotificationIfEnabled(title: String, body: String) {
        guard Defaults[.portForwardShowNotifications] else { return }
        NotificationService.shared.notify(title: title, body: body)
    }
}
