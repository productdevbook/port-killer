import Foundation
import Testing
@testable import PortKiller

/**
 * Regression tests for #75: every tunnel run gets a fresh id, so anything the
 * service keeps per id (Process, Pipe, output task, handler closures) must be
 * released once the process is gone — otherwise it accumulates for the life of the app.
 *
 * `/usr/bin/false` stands in for cloudflared: it ignores the tunnel arguments and exits 1.
 */
@MainActor
struct CloudflaredServiceLifecycleTests {

    @Test("stopTunnel releases an already-exited process and its handlers")
    func stopTunnelReleasesExitedProcess() async throws {
        let service = CloudflaredService(executablePathOverride: "/usr/bin/false")
        let id = UUID()
        await service.setLogHandler(for: id) { _ in }

        let process = try await service.runNamedTunnel(id: id, tunnelName: "test")
        process.waitUntilExit()
        #expect(await service.isTracking(id: id))

        await service.stopTunnel(id: id)

        #expect(await service.isTracking(id: id) == false)
        #expect(await service.trackedProcessCount == 0)
    }

    @Test("stopTunnel clears handlers even when no process was launched")
    func stopTunnelClearsHandlersWithoutProcess() async {
        let service = CloudflaredService(executablePathOverride: "/usr/bin/false")
        let id = UUID()
        await service.setURLHandler(for: id) { _ in }
        await service.setErrorHandler(for: id) { _ in }
        await service.setLogHandler(for: id) { _ in }

        await service.stopTunnel(id: id)

        #expect(await service.isTracking(id: id) == false)
    }

    @Test("A named tunnel whose process exits does not stay tracked")
    func exitedNamedTunnelIsReleased() async throws {
        let service = CloudflaredService(executablePathOverride: "/usr/bin/false")
        let manager = NamedTunnelManager(cloudflaredService: service)
        let tunnel = NamedCloudflareTunnel(tunnelID: UUID().uuidString, name: "test")

        manager.run(tunnel)

        // startNamedTunnel waits ~3s before checking the process.
        let deadline = Date().addingTimeInterval(10)
        while tunnel.status != .error, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(tunnel.status == .error)
        #expect(tunnel.runID == nil)
        #expect(await service.trackedProcessCount == 0)
    }
}
