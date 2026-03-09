import Foundation
import Defaults

extension AppState {
    /// Checks for new ports matching enabled process type notifications.
    /// Call after each scan to detect newly appeared ports.
    func checkProcessTypeNotifications(oldPorts: [PortInfo], newPorts: [PortInfo]) {
        let enabledTypes = Defaults[.notifyProcessTypes]
        guard !enabledTypes.isEmpty else { return }

        let oldPortPids = Set(oldPorts.map { "\($0.port)-\($0.pid)" })

        for port in newPorts {
            let key = "\(port.port)-\(port.pid)"
            guard !oldPortPids.contains(key) else { continue }
            guard enabledTypes.contains(port.processType.rawValue) else { continue }

            NotificationService.shared.notify(
                title: "New \(port.processType.rawValue) on Port \(port.port)",
                body: "\(port.processName) started listening."
            )
        }
    }
}
