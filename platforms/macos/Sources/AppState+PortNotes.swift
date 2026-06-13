import Foundation
import Defaults

extension AppState {
    /// Returns the freeform note for a port, if any
    func portNote(for port: Int) -> String? {
        let note = Defaults[.portNotes][String(port)]
        return (note?.isEmpty ?? true) ? nil : note
    }

    /// Sets a freeform note for a port (empty string clears it)
    func setPortNote(_ note: String, for port: Int) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Defaults[.portNotes].removeValue(forKey: String(port))
        } else {
            Defaults[.portNotes][String(port)] = trimmed
        }
    }

    /// Removes the note for a port
    func removePortNote(for port: Int) {
        Defaults[.portNotes].removeValue(forKey: String(port))
    }
}
