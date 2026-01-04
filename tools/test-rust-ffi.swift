#!/usr/bin/env swift
//
// Test script for Rust FFI
// Compile: swiftc -L.build/rust/lib -lportkiller tools/test-rust-ffi.swift -o .build/test-rust-ffi
//

import Foundation

// MARK: - FFI Declarations

typealias PortKillerHandle = OpaquePointer

struct CPortInfo {
    var port: UInt16
    var pid: UInt32
    var process_name: UnsafeMutablePointer<CChar>?
    var command: UnsafeMutablePointer<CChar>?
    var address: UnsafeMutablePointer<CChar>?
    var process_type: UInt8
    var is_active: Bool
}

struct CPortInfoArray {
    var data: UnsafeMutablePointer<CPortInfo>?
    var len: Int
    var capacity: Int
}

@_silgen_name("portkiller_new")
func portkiller_new() -> PortKillerHandle?

@_silgen_name("portkiller_free")
func portkiller_free(_ handle: PortKillerHandle)

@_silgen_name("portkiller_scan_ports")
func portkiller_scan_ports(_ handle: PortKillerHandle, _ out: UnsafeMutablePointer<CPortInfoArray>) -> Int32

@_silgen_name("portkiller_free_port_array")
func portkiller_free_port_array(_ array: UnsafeMutablePointer<CPortInfoArray>)

@_silgen_name("portkiller_kill_gracefully")
func portkiller_kill_gracefully(_ handle: PortKillerHandle, _ pid: UInt32) -> Int32

@_silgen_name("portkiller_version")
func portkiller_version() -> UnsafePointer<CChar>?

// MARK: - Test

print("╔══════════════════════════════════════════════════════════════════╗")
print("║              PortKiller Rust FFI Test                            ║")
print("╚══════════════════════════════════════════════════════════════════╝")
print("")

// Get version
if let versionPtr = portkiller_version() {
    let version = String(cString: versionPtr)
    print("✓ Library version: \(version)")
} else {
    print("✗ Failed to get version")
    exit(1)
}

// Create handle
guard let handle = portkiller_new() else {
    print("✗ Failed to create PortKiller handle")
    exit(1)
}
print("✓ Created PortKiller handle")

// Scan ports
print("")
print("Scanning ports...")
let arrayPtr = UnsafeMutablePointer<CPortInfoArray>.allocate(capacity: 1)
arrayPtr.initialize(to: CPortInfoArray(data: nil, len: 0, capacity: 0))

let startTime = Date()
let result = portkiller_scan_ports(handle, arrayPtr)
let elapsed = Date().timeIntervalSince(startTime)

if result != 1 {
    print("✗ Scan failed")
    arrayPtr.deallocate()
    portkiller_free(handle)
    exit(1)
}

let ports = arrayPtr.pointee
print("✓ Scan completed in \(String(format: "%.2f", elapsed * 1000))ms")
print("✓ Found \(ports.len) listening ports")

if ports.len > 0, let data = ports.data {
    print("")
    print("┌─────────┬─────────┬────────────────────────────────┬───────────────┐")
    print("│  Port   │   PID   │ Process                        │ Address       │")
    print("├─────────┼─────────┼────────────────────────────────┼───────────────┤")

    for i in 0..<min(Int(ports.len), 15) {
        let port = data[i]
        let portNum = port.port
        let pid = port.pid
        let name = port.process_name.map { String(cString: $0) } ?? "?"
        let addr = port.address.map { String(cString: $0) } ?? "*"

        let truncName = name.count > 30 ? String(name.prefix(27)) + "..." : name
        let paddedName = truncName.padding(toLength: 30, withPad: " ", startingAt: 0)
        let paddedAddr = addr.padding(toLength: 13, withPad: " ", startingAt: 0)
        print("│ \(String(format: "%7d", portNum)) │ \(String(format: "%7d", pid)) │ \(paddedName) │ \(paddedAddr) │")
    }

    if ports.len > 15 {
        print("│   ...   │   ...   │ ... and \(ports.len - 15) more                  │               │")
    }

    print("└─────────┴─────────┴────────────────────────────────┴───────────────┘")
}

// Free resources
portkiller_free_port_array(arrayPtr)
arrayPtr.deallocate()
portkiller_free(handle)

print("")
print("✓ All tests passed!")
