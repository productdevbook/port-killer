import Foundation
import Testing
@testable import PortKiller

/**
 * Tests for PortCustomization: type resolution order, Codable round-trip,
 * and empty-record detection.
 */
struct PortCustomizationTests {

    // MARK: - resolveType

    @Test("Per-port override wins over legacy and detection")
    func portOverrideWins() {
        let type = PortCustomization.resolveType(
            portOverride: .database,
            legacyRaw: ProcessType.system.rawValue,
            processName: "node"
        )
        #expect(type == .database)
    }

    @Test("Legacy per-name override wins over detection")
    func legacyOverrideWins() {
        let type = PortCustomization.resolveType(
            portOverride: nil,
            legacyRaw: ProcessType.webServer.rawValue,
            processName: "node"
        )
        #expect(type == .webServer)
    }

    @Test("Invalid legacy raw value falls through to detection")
    func invalidLegacyFallsThrough() {
        let type = PortCustomization.resolveType(
            portOverride: nil,
            legacyRaw: "Not A Real Type",
            processName: "node"
        )
        #expect(type == .development)
    }

    @Test("No overrides falls back to detection")
    func noOverridesDetects() {
        #expect(PortCustomization.resolveType(portOverride: nil, legacyRaw: nil, processName: "nginx") == .webServer)
        #expect(PortCustomization.resolveType(portOverride: nil, legacyRaw: nil, processName: "mystery") == .other)
    }

    // MARK: - Codable

    @Test("Round-trips through Codable with all fields set")
    func codableRoundTrip() throws {
        let original = PortCustomization(
            name: "My API",
            description: "Local dev server",
            folder: "/Users/me/src/api",
            type: .development
        )
        let decoded = try JSONDecoder().decode(PortCustomization.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test("Round-trips through Codable with all fields nil")
    func codableRoundTripEmpty() throws {
        let original = PortCustomization()
        let decoded = try JSONDecoder().decode(PortCustomization.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    // MARK: - isEmpty

    @Test("isEmpty is true only when every field is nil")
    func isEmptyChecks() {
        #expect(PortCustomization().isEmpty)
        #expect(!PortCustomization(name: "x").isEmpty)
        #expect(!PortCustomization(description: "x").isEmpty)
        #expect(!PortCustomization(folder: "/tmp").isEmpty)
        #expect(!PortCustomization(type: .other).isEmpty)
    }
}
