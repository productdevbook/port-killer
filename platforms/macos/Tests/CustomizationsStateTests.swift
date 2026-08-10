import Foundation
import Testing
import Defaults
@testable import PortKiller

/**
 * Tests for CustomizationsState: persistence round-trips, empty-record
 * removal, input normalization, and legacy label/note migration.
 */
@MainActor
struct CustomizationsStateTests {

    /// Isolated storage keys backed by a throwaway UserDefaults suite
    private struct TestKeys {
        let suiteName = "PortKillerTests-\(UUID().uuidString)"
        let key: Defaults.Key<[String: PortCustomization]>
        let labelsKey: Defaults.Key<[String: String]>
        let notesKey: Defaults.Key<[String: String]>
        let migratedKey: Defaults.Key<Bool>

        init() {
            let suite = UserDefaults(suiteName: suiteName)!
            key = Defaults.Key("portCustomizations", default: [:], suite: suite)
            labelsKey = Defaults.Key("portLabels", default: [:], suite: suite)
            notesKey = Defaults.Key("portNotes", default: [:], suite: suite)
            migratedKey = Defaults.Key("hasMigratedCustomizations", default: false, suite: suite)
        }

        @MainActor
        func makeState() -> CustomizationsState {
            CustomizationsState(
                key: key,
                legacyLabelsKey: labelsKey,
                legacyNotesKey: notesKey,
                migratedFlagKey: migratedKey
            )
        }
    }

    @Test("Set fields persist and reload through a new instance")
    func persistenceRoundTrip() {
        let keys = TestKeys()
        let state = keys.makeState()
        state.setName("My API", for: 3000)
        state.setDescription("Local dev server", for: 3000)
        state.setFolder("/Users/me/src/api", for: 3000)
        state.setType(.database, for: 3000)

        let reloaded = keys.makeState()
        let record = reloaded.customization(for: 3000)
        #expect(record?.name == "My API")
        #expect(record?.description == "Local dev server")
        #expect(record?.folder == "/Users/me/src/api")
        #expect(record?.type == .database)
    }

    @Test("Clearing every field removes the record from storage")
    func emptyRecordRemoved() {
        let keys = TestKeys()
        let state = keys.makeState()
        state.setName("Temp", for: 8080)
        state.setName("", for: 8080)
        #expect(state.customization(for: 8080) == nil)
        #expect(Defaults[keys.key].isEmpty)
    }

    @Test("Names and descriptions are trimmed; whitespace-only clears")
    func normalization() {
        let keys = TestKeys()
        let state = keys.makeState()
        state.setName("  padded  ", for: 3000)
        #expect(state.customization(for: 3000)?.name == "padded")
        state.setDescription("   \n", for: 3000)
        #expect(state.customization(for: 3000)?.description == nil)
    }

    @Test("Init migrates legacy labels and notes once, leaving them intact")
    func migrationOnInit() {
        let keys = TestKeys()
        Defaults[keys.labelsKey] = ["3000": "My App", "9999": ""]
        Defaults[keys.notesKey] = ["3000": "The main app", "4000": "Postgres note"]

        let state = keys.makeState()
        #expect(state.customization(for: 3000)?.name == "My App")
        #expect(state.customization(for: 3000)?.description == "The main app")
        #expect(state.customization(for: 4000)?.description == "Postgres note")
        #expect(state.customization(for: 9999) == nil)
        #expect(Defaults[keys.migratedKey])

        // Legacy keys stay populated so a downgrade still sees its data
        #expect(!Defaults[keys.labelsKey].isEmpty)
        #expect(!Defaults[keys.notesKey].isEmpty)

        // Second init does not re-merge and keeps the records
        let again = keys.makeState()
        #expect(again.customization(for: 3000)?.name == "My App")
    }

    @Test("Deleted values are not resurrected from intact legacy keys")
    func noZombieResurrection() {
        let keys = TestKeys()
        Defaults[keys.labelsKey] = ["3000": "My App"]

        let state = keys.makeState()
        #expect(state.customization(for: 3000)?.name == "My App")
        state.setName("", for: 3000)
        #expect(state.customization(for: 3000) == nil)

        // Relaunch: the migration flag prevents re-importing the legacy label
        let again = keys.makeState()
        #expect(again.customization(for: 3000) == nil)
    }

    @Test("merged() lets existing record fields win over legacy values")
    func mergedExistingWins() {
        let existing = ["3000": PortCustomization(name: "Kept", type: .database)]
        let result = CustomizationsState.merged(
            labels: ["3000": "Legacy Label", "4000": "New Label"],
            notes: ["3000": "Legacy Note"],
            into: existing
        )
        #expect(result["3000"]?.name == "Kept")
        #expect(result["3000"]?.description == "Legacy Note")
        #expect(result["3000"]?.type == .database)
        #expect(result["4000"]?.name == "New Label")
    }
}
