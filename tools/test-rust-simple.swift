#!/usr/bin/env swift
// Simple FFI test - only tests lifecycle functions

import Foundation

typealias PortKillerHandle = OpaquePointer

@_silgen_name("portkiller_new")
func portkiller_new() -> PortKillerHandle?

@_silgen_name("portkiller_free")
func portkiller_free(_ handle: PortKillerHandle)

@_silgen_name("portkiller_version")
func portkiller_version() -> UnsafePointer<CChar>?

print("Testing version...")
if let versionPtr = portkiller_version() {
    let version = String(cString: versionPtr)
    print("✓ Version: \(version)")
}

print("Testing handle creation...")
guard let handle = portkiller_new() else {
    print("✗ Failed to create handle")
    exit(1)
}
print("✓ Handle created: \(handle)")

print("Testing handle free...")
portkiller_free(handle)
print("✓ Handle freed")

print("")
print("All basic tests passed!")
