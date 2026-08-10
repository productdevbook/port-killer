/**
 * CustomizationsState.swift
 * PortKiller
 *
 * Manages per-port customizations (name, description, folder, type) with
 * persistence. Observable so edits re-render views immediately.
 */

import Foundation
import Defaults

/// Manages per-port customizations
@Observable
@MainActor
final class CustomizationsState {
    /// Storage key, injectable for tests
    @ObservationIgnored private let key: Defaults.Key<[String: PortCustomization]>

    /// Cached customizations keyed by port number, persisted on mutation
    private(set) var customizations: [Int: PortCustomization] = [:]

    /// Initialize with storage keys, migrating legacy labels/notes first
    ///
    /// - Parameters:
    ///   - key: Storage key for customizations (defaults to the app key)
    ///   - legacyLabelsKey: Legacy port labels key to migrate and clear
    ///   - legacyNotesKey: Legacy port notes key to migrate and clear
    init(
        key: Defaults.Key<[String: PortCustomization]> = .portCustomizations,
        legacyLabelsKey: Defaults.Key<[String: String]> = .portLabels,
        legacyNotesKey: Defaults.Key<[String: String]> = .portNotes
    ) {
        self.key = key

        let labels = Defaults[legacyLabelsKey]
        let notes = Defaults[legacyNotesKey]
        if !labels.isEmpty || !notes.isEmpty {
            Defaults[key] = Self.merged(labels: labels, notes: notes, into: Defaults[key])
            Defaults[legacyLabelsKey] = [:]
            Defaults[legacyNotesKey] = [:]
        }

        customizations = Defaults[key].reduce(into: [:]) { result, entry in
            if let port = Int(entry.key) { result[port] = entry.value }
        }
    }

    /// Returns the customization for a port, if any
    func customization(for port: Int) -> PortCustomization? {
        customizations[port]
    }

    /// Mutates a port's customization; empty records are removed, then persisted
    func update(for port: Int, _ mutate: (inout PortCustomization) -> Void) {
        var record = customizations[port] ?? PortCustomization()
        mutate(&record)
        customizations[port] = record.isEmpty ? nil : record
        Defaults[key] = customizations.reduce(into: [:]) { result, entry in
            result[String(entry.key)] = entry.value
        }
    }

    /// Sets the custom display name (trimmed; empty clears it)
    func setName(_ raw: String, for port: Int) {
        update(for: port) { $0.name = Self.normalized(raw) }
    }

    /// Sets the description (trimmed; empty clears it)
    func setDescription(_ raw: String, for port: Int) {
        update(for: port) { $0.description = Self.normalized(raw) }
    }

    /// Sets or clears the manually associated folder path
    func setFolder(_ path: String?, for port: Int) {
        update(for: port) { $0.folder = path }
    }

    /// Sets or clears the process type override
    func setType(_ type: ProcessType?, for port: Int) {
        update(for: port) { $0.type = type }
    }

    private static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Migration

    /// Merges legacy label/note dictionaries into customization records.
    /// Existing record fields win over legacy values; empty strings are skipped.
    static func merged(
        labels: [String: String],
        notes: [String: String],
        into existing: [String: PortCustomization]
    ) -> [String: PortCustomization] {
        var result = existing
        for (port, label) in labels where !label.isEmpty {
            var record = result[port] ?? PortCustomization()
            record.name = record.name ?? label
            result[port] = record
        }
        for (port, note) in notes where !note.isEmpty {
            var record = result[port] ?? PortCustomization()
            record.description = record.description ?? note
            result[port] = record
        }
        return result
    }
}
