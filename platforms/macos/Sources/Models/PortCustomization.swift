/**
 * PortCustomization.swift
 * PortKiller
 *
 * Per-port user customization: display name, description, project folder,
 * and process type override. Stored in Defaults keyed by port number.
 */

import Foundation
import Defaults

/// User customization for a specific port
///
/// All fields are optional; a record with no fields set is removed from storage.
/// The custom name replaces the process name in port rows, the description is
/// shown in the detail view, the folder overrides the auto-detected working
/// directory, and the type overrides automatic process type detection.
struct PortCustomization: Codable, Hashable, Sendable, Defaults.Serializable {
    /// Custom display name shown in place of the process name
    var name: String?

    /// Brief description shown in the detail view
    var description: String?

    /// Manually associated folder path (overrides the detected working directory)
    var folder: String?

    /// Process type override for this port
    var type: ProcessType?

    /// Whether every field is unset (empty records are dropped from storage)
    var isEmpty: Bool {
        name == nil && description == nil && folder == nil && type == nil
    }

    /// Resolve the effective process type for a port
    ///
    /// Resolution order: per-port override → legacy per-process-name override
    /// (kept read-only for backwards compatibility) → automatic detection.
    ///
    /// - Parameters:
    ///   - portOverride: The per-port type override, if any
    ///   - legacyRaw: Raw value from the legacy `processTypeOverrides` dictionary
    ///   - processName: The process name for automatic detection
    /// - Returns: The effective ProcessType
    static func resolveType(portOverride: ProcessType?, legacyRaw: String?, processName: String) -> ProcessType {
        portOverride
            ?? legacyRaw.flatMap(ProcessType.init(rawValue:))
            ?? ProcessType.detect(from: processName)
    }
}
