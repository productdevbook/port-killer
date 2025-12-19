/**
 * RustPortScanner.swift
 * PortKiller
 *
 * Swift wrapper around the Rust portkiller-ffi library.
 * Provides the same interface as the native Swift PortScanner but uses
 * the Rust implementation for port scanning and process killing.
 */

import Foundation

/// Port scanner that uses the Rust backend via UniFFI bindings.
///
/// This actor wraps the Rust `RustScanner` and provides a compatible
/// interface with the native Swift `PortScanner`. Use this when you want
/// to leverage the Rust implementation.
///
/// Thread Safety:
/// This is an actor, so all methods are isolated and can be called safely from any context.
actor RustPortScanner {

    /// The underlying Rust scanner instance
    private let scanner: RustScanner

    /// Initialize the Rust port scanner
    init() {
        self.scanner = RustScanner()
    }

    /// Scans all listening TCP ports using the Rust backend.
    ///
    /// Uses the Rust `lsof` parser which provides the same output as the
    /// native Swift implementation.
    ///
    /// - Returns: Array of PortInfo objects representing all listening ports
    func scanPorts() async -> [PortInfo] {
        do {
            let rustPorts = try scanner.scanPorts()
            return rustPorts.map { rustPort in
                // Convert from RustPortInfo (UniFFI) to Swift PortInfo
                PortInfo.active(
                    port: Int(rustPort.port),
                    pid: Int(rustPort.pid),
                    processName: rustPort.processName,
                    address: rustPort.address,
                    user: rustPort.user,
                    command: rustPort.command,
                    fd: rustPort.fd
                )
            }
        } catch {
            // Log error in debug mode
            #if DEBUG
            print("RustPortScanner.scanPorts error: \(error)")
            #endif
            return []
        }
    }

    /// Kill a process by PID.
    ///
    /// - Parameters:
    ///   - pid: The process ID to kill
    ///   - force: If true, sends SIGKILL immediately; otherwise SIGTERM
    /// - Returns: True if the kill signal was sent successfully
    func killProcess(pid: Int, force: Bool = false) async -> Bool {
        do {
            if force {
                return try scanner.forceKillProcess(pid: UInt32(pid))
            } else {
                return try scanner.killProcess(pid: UInt32(pid))
            }
        } catch {
            #if DEBUG
            print("RustPortScanner.killProcess error: \(error)")
            #endif
            return false
        }
    }

    /// Kill a process gracefully using the two-stage approach.
    ///
    /// Strategy:
    /// 1. Send SIGTERM (graceful shutdown signal)
    /// 2. Wait for 500ms
    /// 3. Send SIGKILL if the process is still running
    ///
    /// - Parameter pid: The process ID to kill
    /// - Returns: True if the process was killed
    func killProcessGracefully(pid: Int) async -> Bool {
        do {
            return try scanner.killProcess(pid: UInt32(pid))
        } catch {
            #if DEBUG
            print("RustPortScanner.killProcessGracefully error: \(error)")
            #endif
            return false
        }
    }

    /// Check if a process is currently running.
    ///
    /// - Parameter pid: The process ID to check
    /// - Returns: True if the process exists
    func isProcessRunning(pid: Int) -> Bool {
        scanner.isProcessRunning(pid: UInt32(pid))
    }
}

// MARK: - PortInfo Extension for Rust Conversion

extension PortInfo {
    /// Create a PortInfo from Rust FFI RustPortInfo
    ///
    /// - Parameter rustPort: The UniFFI-generated RustPortInfo from Rust
    /// - Returns: A Swift PortInfo instance
    static func fromRust(_ rustPort: RustPortInfo) -> PortInfo {
        PortInfo.active(
            port: Int(rustPort.port),
            pid: Int(rustPort.pid),
            processName: rustPort.processName,
            address: rustPort.address,
            user: rustPort.user,
            command: rustPort.command,
            fd: rustPort.fd
        )
    }
}

