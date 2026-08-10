import Foundation

extension AppState {
    /// Returns the customization for a port, if any
    func customization(for port: Int) -> PortCustomization? {
        customizationsState.customization(for: port)
    }

    /// Display name for a port row: custom name, or the real process name
    func displayName(for port: PortInfo) -> String {
        customization(for: port.port)?.name ?? port.processName
    }

    /// Effective folder for a port: manual override, or nothing yet
    func folder(for port: PortInfo) -> String? {
        customization(for: port.port)?.folder
    }

    /// Sets or clears the per-port type override.
    /// Type is baked into PortInfo at scan time, so trigger an immediate rescan.
    func setTypeOverride(_ type: ProcessType?, for port: Int) {
        customizationsState.setType(type, for: port)
        Task { _ = await refresh() }
    }
}
