import Foundation

// FFI declarations for Rust backend
private typealias PortKillerHandle = OpaquePointer

@_silgen_name("portkiller_new")
private func portkiller_new() -> PortKillerHandle?

@_silgen_name("portkiller_free")
private func portkiller_free(_ handle: PortKillerHandle)

@_silgen_name("portkiller_kill_processes_on_port")
private func portkiller_kill_processes_on_port(_ handle: PortKillerHandle, _ port: UInt16) -> Int32

extension PortForwardProcessManager {
    /// Kills any process using the specified port.
    ///
    /// Uses the Rust backend which:
    /// 1. Finds all PIDs on the port (via lsof)
    /// 2. Sends SIGTERM to each
    /// 3. Waits 300ms
    /// 4. Sends SIGKILL to any still running
    func killProcessOnPort(_ port: Int) async {
        guard let handle = portkiller_new() else { return }
        defer { portkiller_free(handle) }

        _ = portkiller_kill_processes_on_port(handle, UInt16(port))
    }
}
