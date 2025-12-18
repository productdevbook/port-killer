import Foundation
import AppKit

// MARK: - Tunnel Manager

/// Manages Cloudflare Quick Tunnel connections
@Observable
@MainActor
final class TunnelManager {
    /// Active tunnel states
    var tunnels: [CloudflareTunnelState] = []

    /// The cloudflared service actor
    let cloudflaredService = CloudflaredService()

    /// Number of currently active tunnels
    var activeTunnelCount: Int {
        tunnels.filter { $0.status == .active }.count
    }

    /// Cached installation status (observable for UI updates)
    private(set) var isCloudflaredInstalled: Bool = false

    // MARK: - Initialization

    init() {
        // Check initial installation status
        isCloudflaredInstalled = cloudflaredService.isInstalled

        // Clean up any orphaned tunnel processes from previous crashed sessions
        Task {
            await cleanupOrphanedTunnels()
        }
    }

    /// Re-check cloudflared installation status (call after user installs)
    func recheckInstallation() {
        isCloudflaredInstalled = cloudflaredService.isInstalled
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
    /// - Parameters:
    ///   - port: The local port to expose
    ///   - portInfoId: Optional reference to the PortInfo this tunnel is for
    func startTunnel(for port: Int, portInfoId: UUID? = nil) {
        // Check if tunnel already exists for this port
        if let existing = tunnels.first(where: { $0.port == port && $0.status != .error }) {
            // Already tunneling this port - just copy the URL if available
            if let url = existing.tunnelURL {
                ClipboardService.copy(url)
            }
            return
        }

        let state = CloudflareTunnelState(port: port, portInfoId: portInfoId)
        tunnels.append(state)

        state.status = .starting

        Task {
            await cloudflaredService.setURLHandler(for: state.id) { [weak self, weak state] url in
                Task { @MainActor in
                    guard let state = state else { return }
                    state.tunnelURL = url
                    state.status = .active
                    state.startTime = Date()

                    // Auto-copy URL to clipboard
                    ClipboardService.copy(url)

                    // Send notification
                    NotificationService.shared.notify(
                        title: "Tunnel Active",
                        body: "Port \(state.port) available at \(self?.shortenedURL(url) ?? url)"
                    )
                }
            }

            await cloudflaredService.setErrorHandler(for: state.id) { [weak state] error in
                Task { @MainActor in
                    guard let state = state else { return }
                    state.lastError = error
                    if state.status != .active {
                        state.status = .error
                    }
                }
            }

            do {
                let process = try await cloudflaredService.startTunnel(id: state.id, port: port)

                // Wait a bit to see if process starts successfully
                try? await Task.sleep(for: .seconds(3))

                if !process.isRunning && state.status != .active {
                    state.status = .error
                    state.lastError = "Process terminated unexpectedly"
                }
            } catch {
                state.status = .error
                state.lastError = error.localizedDescription
            }
        }
    }

    /// Stop the tunnel for the specified port
    func stopTunnel(for port: Int) {
        guard let state = tunnels.first(where: { $0.port == port }) else { return }
        stopTunnel(id: state.id)
    }

    /// Stop a tunnel by its ID
    func stopTunnel(id: UUID) {
        guard let index = tunnels.firstIndex(where: { $0.id == id }) else { return }
        let state = tunnels[index]

        state.status = .stopping

        Task {
            await cloudflaredService.stopTunnel(id: id)
            await MainActor.run {
                if let idx = tunnels.firstIndex(where: { $0.id == id }) {
                    tunnels.remove(at: idx)
                }
            }
        }
    }

    /// Stop all active tunnels
    func stopAllTunnels() async {
        for tunnel in tunnels {
            tunnel.status = .stopping
        }
        await cloudflaredService.stopAllTunnels()
        tunnels.removeAll()
    }

    /// Get the tunnel state for a port
    func tunnelState(for port: Int) -> CloudflareTunnelState? {
        tunnels.first { $0.port == port }
    }

    /// Check if a port has an active tunnel
    func hasTunnel(for port: Int) -> Bool {
        tunnels.contains { $0.port == port && $0.status != .error }
    }

    /// Copy the tunnel URL for a port to clipboard
    func copyURL(for port: Int) {
        guard let tunnel = tunnelState(for: port),
              let url = tunnel.tunnelURL else { return }
        ClipboardService.copy(url)
    }

    /// Open the tunnel URL in browser
    func openURL(for port: Int) {
        guard let tunnel = tunnelState(for: port),
              let urlString = tunnel.tunnelURL,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    /// Shorten a trycloudflare.com URL for display
    private func shortenedURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
