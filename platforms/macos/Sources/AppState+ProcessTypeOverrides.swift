import Foundation
import Defaults

extension AppState {
    /// Sets a process type override for a given process name
    func setProcessTypeOverride(processName: String, type: ProcessType) {
        Defaults[.processTypeOverrides][processName] = type.rawValue
    }

    /// Clears the process type override for a given process name
    func clearProcessTypeOverride(processName: String) {
        Defaults[.processTypeOverrides].removeValue(forKey: processName)
    }

    /// Returns the overridden process type for a process name, if any
    func processTypeOverride(for processName: String) -> ProcessType? {
        guard let rawValue = Defaults[.processTypeOverrides][processName] else { return nil }
        return ProcessType(rawValue: rawValue)
    }
}
