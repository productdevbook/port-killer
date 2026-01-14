import Foundation

extension PortForwardManager {
    /// Starts the connection monitoring task.
    func startMonitoring() {
        isMonitoring = true
        monitorTask = Task {
            while !Task.isCancelled && isMonitoring {
                await checkConnections()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Stops the connection monitoring task.
    func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Checks all connections and reconnects if needed.
    func checkConnections() async {
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
                let wasConnected = state.isFullyConnected
                state.lastError = "kubectl error"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                if wasConnected {
                    sendDisconnectNotificationIfEnabled(for: state.config, wasIntentional: state.isIntentionallyStopped)
                }
                await processManager.killProcesses(for: state.id)
                await processManager.clearError(for: state.id)
                startConnection(state.id)
                continue
            }

            // Reconnect if process died
            if state.portForwardStatus == .connected && !processRunning {
                let wasConnected = state.isFullyConnected
                state.lastError = "Process terminated"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                if wasConnected {
                    sendDisconnectNotificationIfEnabled(for: state.config, wasIntentional: state.isIntentionallyStopped)
                }
                startConnection(state.id)
                continue
            }

            // Reconnect if port not responding
            if state.portForwardStatus == .connected && !pfWorking {
                let wasConnected = state.isFullyConnected
                state.lastError = "Connection lost"
                state.portForwardStatus = .disconnected
                state.proxyStatus = .disconnected
                if wasConnected {
                    sendDisconnectNotificationIfEnabled(for: state.config, wasIntentional: state.isIntentionallyStopped)
                }
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

    /// Checks a direct exec connection and reconnects if needed.
    func checkDirectExecConnection(_ state: PortForwardConnectionState) async {
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
            let wasConnected = state.isFullyConnected
            state.lastError = "Proxy error"
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            if wasConnected {
                sendDisconnectNotificationIfEnabled(for: state.config, wasIntentional: state.isIntentionallyStopped)
            }
            await processManager.killProcesses(for: state.id)
            await processManager.clearError(for: state.id)
            startConnection(state.id)
            return
        }

        if state.proxyStatus == .connected && !proxyRunning {
            let wasConnected = state.isFullyConnected
            state.lastError = "Proxy terminated"
            state.portForwardStatus = .disconnected
            state.proxyStatus = .disconnected
            if wasConnected {
                sendDisconnectNotificationIfEnabled(for: state.config, wasIntentional: state.isIntentionallyStopped)
            }
            startConnection(state.id)
            return
        }
    }
}
