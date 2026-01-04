import Foundation

// MARK: - Rust FFI Type Declarations

private typealias PortKillerHandle = OpaquePointer

private struct CPortInfo {
    var port: UInt16
    var pid: UInt32
    var process_name: UnsafeMutablePointer<CChar>?
    var command: UnsafeMutablePointer<CChar>?
    var address: UnsafeMutablePointer<CChar>?
    var process_type: UInt8
    var is_active: Bool
}

private struct CPortInfoArray {
    var data: UnsafeMutablePointer<CPortInfo>?
    var len: Int
    var capacity: Int
}

// FFI function declarations - these link to libportkiller.a
@_silgen_name("portkiller_new")
private func portkiller_new() -> PortKillerHandle?

@_silgen_name("portkiller_free")
private func portkiller_free(_ handle: PortKillerHandle)

@_silgen_name("portkiller_scan_ports")
private func portkiller_scan_ports(_ handle: PortKillerHandle, _ out: UnsafeMutablePointer<CPortInfoArray>) -> Int32

@_silgen_name("portkiller_free_port_array")
private func portkiller_free_port_array(_ array: UnsafeMutablePointer<CPortInfoArray>)

@_silgen_name("portkiller_kill_gracefully")
private func portkiller_kill_gracefully(_ handle: PortKillerHandle, _ pid: UInt32) -> Int32

@_silgen_name("portkiller_kill_force")
private func portkiller_kill_force(_ handle: PortKillerHandle, _ pid: UInt32) -> Int32

@_silgen_name("portkiller_version")
private func portkiller_version() -> UnsafePointer<CChar>?

@_silgen_name("portkiller_kill_processes_on_port")
private func portkiller_kill_processes_on_port(_ handle: PortKillerHandle, _ port: UInt16) -> Int32

// MARK: - Handle Wrapper

/// Thread-safe wrapper for the Rust handle
private final class RustHandle: @unchecked Sendable {
    let pointer: PortKillerHandle?

    init() {
        self.pointer = portkiller_new()
        if pointer == nil {
            print("⚠️ PortScanner: Failed to initialize Rust backend")
        }
    }

    deinit {
        if let pointer = pointer {
            portkiller_free(pointer)
        }
    }
}

// MARK: - PortScanner

/**
 * PortScanner is a Swift actor that safely scans system ports and manages process termination.
 *
 * This implementation uses a Rust backend for cross-platform compatibility.
 * The Rust library handles the low-level system calls (lsof/netstat, kill/taskkill).
 *
 * Key responsibilities:
 * - Scan all listening TCP ports
 * - Kill processes gracefully (SIGTERM then SIGKILL)
 * - Provide thread-safe access via actor isolation
 *
 * Build Requirements:
 * - Run `./scripts/build-rust.sh` to build libportkiller.a
 * - Link the library to your target
 */
actor PortScanner {

    /// Wrapper for the Rust handle (Sendable-safe)
    private let rustHandle: RustHandle

    /// Rust library version
    nonisolated var version: String {
        guard let ptr = portkiller_version() else { return "unknown" }
        return String(cString: ptr)
    }

    init() {
        self.rustHandle = RustHandle()
    }

    /**
     * Scans all listening TCP ports.
     *
     * Uses the Rust backend which executes:
     * - macOS: `lsof -iTCP -sTCP:LISTEN -P -n +c 0`
     * - Windows: `netstat -ano`
     *
     * @returns Array of PortInfo objects representing all listening ports
     */
    func scanPorts() async -> [PortInfo] {
        guard let handle = rustHandle.pointer else {
            return []
        }

        // Use autoreleasepool to ensure timely cleanup of temporary objects
        return autoreleasepool {
            // Allocate on heap to avoid Swift/Rust struct layout issues
            let arrayPtr = UnsafeMutablePointer<CPortInfoArray>.allocate(capacity: 1)
            arrayPtr.initialize(to: CPortInfoArray(data: nil, len: 0, capacity: 0))
            defer {
                portkiller_free_port_array(arrayPtr)
                arrayPtr.deallocate()
            }

            let result = portkiller_scan_ports(handle, arrayPtr)
            guard result == 1 else { return [] }

            let cArray = arrayPtr.pointee
            guard let data = cArray.data, cArray.len > 0 else { return [] }

            // Convert C array to Swift array
            var ports: [PortInfo] = []
            ports.reserveCapacity(cArray.len)

            for i in 0..<cArray.len {
                let cPort = data[i]

                let processName = cPort.process_name.map { String(cString: $0) } ?? "Unknown"
                let command = cPort.command.map { String(cString: $0) } ?? processName
                let address = cPort.address.map { String(cString: $0) } ?? "*"

                // Create PortInfo using the active factory method
                let port = PortInfo.active(
                    port: Int(cPort.port),
                    pid: Int(cPort.pid),
                    processName: processName,
                    address: address,
                    user: "",  // Rust backend doesn't provide user info
                    command: command,
                    fd: ""     // Rust backend doesn't provide fd info
                )

                ports.append(port)
            }

            return ports
        }
    }

    /**
     * Kills a process by sending a termination signal.
     *
     * Uses the Rust backend which executes:
     * - macOS: `kill -15 <PID>` (SIGTERM) or `kill -9 <PID>` (SIGKILL)
     * - Windows: `taskkill /PID <PID>` or `taskkill /PID <PID> /F`
     *
     * @param pid - The process ID to kill
     * @param force - If true, sends SIGKILL (-9) instead of SIGTERM (-15)
     * @returns True if the kill command executed successfully
     */
    func killProcess(pid: Int, force: Bool = false) async -> Bool {
        guard let handle = rustHandle.pointer else { return false }

        if force {
            return portkiller_kill_force(handle, UInt32(pid)) == 1
        } else {
            // For non-force, just send SIGTERM
            return portkiller_kill_gracefully(handle, UInt32(pid)) == 1
        }
    }

    /**
     * Attempts to kill a process gracefully, falling back to force kill if needed.
     *
     * Uses the Rust backend which:
     * 1. Sends SIGTERM (graceful shutdown signal)
     * 2. Waits 500ms for process to clean up
     * 3. Sends SIGKILL (immediate termination)
     *
     * @param pid - The process ID to kill
     * @returns True if the process was killed
     */
    func killProcessGracefully(pid: Int) async -> Bool {
        guard let handle = rustHandle.pointer else { return false }
        return portkiller_kill_gracefully(handle, UInt32(pid)) == 1
    }

    /**
     * Kills all processes using a specific port.
     *
     * Uses the Rust backend which:
     * 1. Finds all PIDs on the port (via lsof)
     * 2. Sends SIGTERM to each
     * 3. Waits 300ms
     * 4. Sends SIGKILL to any still running
     *
     * @param port - The port number
     * @returns True if at least one process was killed
     */
    func killProcessesOnPort(_ port: Int) async -> Bool {
        guard let handle = rustHandle.pointer else { return false }
        return portkiller_kill_processes_on_port(handle, UInt16(port)) == 1
    }
}
