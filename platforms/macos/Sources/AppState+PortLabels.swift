import Foundation
import Defaults

extension AppState {
    /// Returns the custom label for a port, if any
    func portLabel(for port: Int) -> String? {
        let label = Defaults[.portLabels][String(port)]
        return (label?.isEmpty ?? true) ? nil : label
    }

    /// Sets a custom label for a port
    func setPortLabel(_ label: String, for port: Int) {
        if label.isEmpty {
            Defaults[.portLabels].removeValue(forKey: String(port))
        } else {
            Defaults[.portLabels][String(port)] = label
        }
    }

    /// Removes the custom label for a port
    func removePortLabel(for port: Int) {
        Defaults[.portLabels].removeValue(forKey: String(port))
    }
}
