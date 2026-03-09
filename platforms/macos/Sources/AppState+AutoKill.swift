import Foundation
import Defaults

extension AppState {
    /// Tracks when ports were first seen (port-pid key → first seen date).
    /// Stored on AppState as a non-observed property.
    private static var portFirstSeen: [String: Date] = [:]

    /// Checks auto-kill rules against current ports and kills matches that exceed their timeout.
    func checkAutoKillRules() {
        let rules = Defaults[.autoKillRules]
        guard !rules.isEmpty else { return }

        let enabledRules = rules.filter(\.isEnabled)
        guard !enabledRules.isEmpty else { return }

        let now = Date()

        // Update first-seen tracking
        let currentKeys = Set(ports.map { "\($0.port)-\($0.pid)" })
        // Remove stale entries
        Self.portFirstSeen = Self.portFirstSeen.filter { currentKeys.contains($0.key) }
        // Add new entries
        for port in ports {
            let key = "\(port.port)-\(port.pid)"
            if Self.portFirstSeen[key] == nil {
                Self.portFirstSeen[key] = now
            }
        }

        // Check rules
        for port in ports {
            let key = "\(port.port)-\(port.pid)"
            guard let firstSeen = Self.portFirstSeen[key] else { continue }

            for rule in enabledRules {
                guard rule.matches(port) else { continue }

                let elapsed = now.timeIntervalSince(firstSeen) / 60.0
                guard elapsed >= Double(rule.timeoutMinutes) else { continue }

                // Notify and kill
                if rule.notifyBeforeKill {
                    NotificationService.shared.notify(
                        title: "Auto-Kill: \(port.processName)",
                        body: "Port \(port.port) killed after \(rule.timeoutMinutes) min (rule: \(rule.name))"
                    )
                }

                Task {
                    await killPort(port)
                }

                // Remove from tracking so we don't re-trigger
                Self.portFirstSeen.removeValue(forKey: key)
                break // Only apply first matching rule
            }
        }
    }
}
