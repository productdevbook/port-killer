import AppKit
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

    /// Prompts user to set a port label using NSAlert
    func promptForPortLabel(port: Int) {
        let alert = NSAlert()
        alert.messageText = "Set Label for Port \(port)"
        alert.informativeText = "Enter a custom name to identify this port."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "e.g., Frontend Dev Server"
        textField.stringValue = portLabel(for: port) ?? ""
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        if alert.runModal() == .alertFirstButtonReturn {
            setPortLabel(textField.stringValue, for: port)
        }
    }
}
