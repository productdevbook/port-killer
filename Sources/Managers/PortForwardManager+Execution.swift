import Foundation
import Defaults

extension PortForwardManager {
    /// Runs the port forward process for a connection.
    func runPortForward(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
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
                        await self.runProxy(for: state, config: config)
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

    /// Runs the direct exec proxy for multi-connection support.
    func runDirectExecProxy(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
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

    /// Runs the socat proxy process.
    func runProxy(for state: PortForwardConnectionState, config: PortForwardConnectionConfig) async {
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

    /// Sends a notification if notifications are enabled.
    func sendNotificationIfEnabled(title: String, body: String) {
        guard Defaults[.portForwardShowNotifications] else { return }
        NotificationService.shared.notify(title: title, body: body)
    }
}
