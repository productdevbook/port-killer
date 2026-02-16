import Foundation
import AppKit

// MARK: - Tunnel Manager

/// Manages Cloudflare Quick Tunnel connections
/// Coordinates between TunnelState (UI) and CloudflaredService (process management)
@Observable
@MainActor
final class TunnelManager {
    /// Observable state for UI (extracted)
    let state: TunnelState

    /// The cloudflared service actor
    let cloudflaredService: CloudflaredService

    /// Task for cleaning up orphaned tunnels from previous sessions
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    // MARK: - Backward Compatibility Accessors

    /// Active tunnel states (delegates to state)
    var tunnels: [CloudflareTunnelState] {
        get { state.tunnels }
        set { state.tunnels = newValue }
    }

    /// Number of currently active tunnels
    var activeTunnelCount: Int {
        state.activeTunnelCount
    }

    /// Cached installation status
    var isCloudflaredInstalled: Bool {
        state.isCloudflaredInstalled
    }

    // MARK: - Initialization

    init(
        state: TunnelState = TunnelState(),
        cloudflaredService: CloudflaredService = CloudflaredService()
    ) {
        self.state = state
        self.cloudflaredService = cloudflaredService

        // Check initial installation status
        state.setInstalled(cloudflaredService.isInstalled)

        // Clean up any orphaned tunnel processes from previous crashed sessions
        cleanupTask = Task {
            await cleanupOrphanedTunnels()
        }
    }

    /// Re-check cloudflared installation status (call after user installs)
    func recheckInstallation() {
        state.setInstalled(cloudflaredService.isInstalled)
    }

    /// Kill any stray cloudflared tunnel processes from previous sessions
    private func cleanupOrphanedTunnels() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-9", "-f", "cloudflared.*tunnel.*--url"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Ignore errors - process may not exist
        }
    }

    // MARK: - Tunnel Operations

    /// Start a tunnel for the specified port
    func startTunnel(for port: Int, portInfoId: String? = nil) {
        Task {
            await cleanupTask?.value
            await _startTunnelImpl(for: port, portInfoId: portInfoId)
        }
    }

    /// Internal implementation of startTunnel after cleanup is complete
    private func _startTunnelImpl(for port: Int, portInfoId: String? = nil) async {
        // Check if tunnel already exists for this port
        if let existing = state.tunnel(for: port) {
            if existing.status != .error {
                if let url = existing.tunnelURL {
                    ClipboardService.copy(url)
                }
                return
            }
            // Prevent accumulating stale error entries for repeated retries.
            state.removeTunnel(id: existing.id)
        }

        let tunnelState = CloudflareTunnelState(port: port, portInfoId: portInfoId)
        state.addTunnel(tunnelState)
        tunnelState.status = .starting

        Task { [weak self, weak tunnelState] in
            guard let self = self, let tunnelState = tunnelState else { return }

            // Set URL handler with proper weak capture in inner Task
            let urlHandler: @Sendable (String) -> Void = { [weak self, weak tunnelState] url in
                guard let tunnelState = tunnelState else { return }
                Task { @MainActor [weak self, weak tunnelState] in
                    guard let tunnelState = tunnelState else { return }
                    tunnelState.tunnelURL = url
                    tunnelState.status = .active
                    tunnelState.startTime = Date()
                    ClipboardService.copy(url)
                    NotificationService.shared.notify(
                        title: "Tunnel Active",
                        body: "Port \(tunnelState.port) available at \(self?.shortenedURL(url) ?? url)"
                    )
                }
            }
            await self.cloudflaredService.setURLHandler(for: tunnelState.id, handler: urlHandler)

            // Set error handler with proper weak capture in inner Task
            let errorHandler: @Sendable (String) -> Void = { [weak tunnelState] error in
                guard let tunnelState = tunnelState else { return }
                Task { @MainActor [weak tunnelState] in
                    guard let tunnelState = tunnelState else { return }
                    tunnelState.lastError = error
                    if tunnelState.status != .active {
                        tunnelState.status = .error
                    }
                }
            }
            await self.cloudflaredService.setErrorHandler(for: tunnelState.id, handler: errorHandler)

            do {
                let process = try await self.cloudflaredService.startTunnel(id: tunnelState.id, port: port)
                try? await Task.sleep(for: .seconds(3))

                if !process.isRunning && tunnelState.status != .active {
                    // Clean up handlers when process terminates unexpectedly
                    await self.cloudflaredService.removeHandlers(for: tunnelState.id)
                    await MainActor.run {
                        tunnelState.status = .error
                        tunnelState.lastError = "Process terminated unexpectedly"
                    }
                }
            } catch {
                // Clean up handlers on error
                await self.cloudflaredService.removeHandlers(for: tunnelState.id)
                await MainActor.run {
                    tunnelState.status = .error
                    tunnelState.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Stop the tunnel for the specified port
    func stopTunnel(for port: Int) {
        guard let tunnel = state.tunnel(for: port) else { return }
        stopTunnel(id: tunnel.id)
    }

    /// Stop a tunnel by its ID
    func stopTunnel(id: UUID) {
        guard let tunnel = tunnels.first(where: { $0.id == id }) else { return }
        tunnel.status = .stopping

        Task {
            await cloudflaredService.stopTunnel(id: id)
            await MainActor.run {
                state.removeTunnel(id: id)
            }
        }
    }

    /// Stop all active tunnels
    func stopAllTunnels() async {
        for tunnel in tunnels {
            tunnel.status = .stopping
        }
        await cloudflaredService.stopAllTunnels()
        state.removeAllTunnels()
    }

    /// Get the tunnel state for a port
    func tunnelState(for port: Int) -> CloudflareTunnelState? {
        state.tunnel(for: port)
    }

    /// Check if a port has an active tunnel
    func hasTunnel(for port: Int) -> Bool {
        state.hasTunnel(for: port)
    }

    /// Copy the tunnel URL for a port to clipboard
    func copyURL(for port: Int) {
        guard let tunnel = state.tunnel(for: port),
              let url = tunnel.tunnelURL else { return }
        ClipboardService.copy(url)
    }

    /// Open the tunnel URL in browser
    func openURL(for port: Int) {
        guard let tunnel = state.tunnel(for: port),
              let urlString = tunnel.tunnelURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private func shortenedURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
