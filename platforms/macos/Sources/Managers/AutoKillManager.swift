import Foundation
import Defaults

/// Evaluates auto-kill rules against the current port list and kills ports that have
/// been listening longer than their rule's timeout.
///
/// Extracted from `AppState` so the first-seen tracking is instance state (not a global
/// static) and the notification dependency is injectable.
@MainActor
final class AutoKillManager {
    /// Tracks when each port was first seen (`"port-pid"` → first seen date).
    private var portFirstSeen: [String: Date] = [:]

    private let notificationService: any NotificationServiceProtocol

    init(notificationService: any NotificationServiceProtocol = NotificationService.shared) {
        self.notificationService = notificationService
    }

    /// Checks auto-kill rules against `ports`, invoking `kill` for matches that exceed
    /// their timeout. `kill` is called at most once per matching port.
    func check(ports: [PortInfo], kill: @escaping (PortInfo) -> Void) {
        let enabledRules = Defaults[.autoKillRules].filter(\.isEnabled)
        guard !enabledRules.isEmpty else { return }

        let now = Date()

        // Update first-seen tracking: drop ports that are gone, stamp newly seen ones.
        let currentKeys = Set(ports.map(Self.key))
        portFirstSeen = portFirstSeen.filter { currentKeys.contains($0.key) }
        for port in ports {
            let key = Self.key(for: port)
            if portFirstSeen[key] == nil {
                portFirstSeen[key] = now
            }
        }

        for port in ports {
            let key = Self.key(for: port)
            guard let firstSeen = portFirstSeen[key] else { continue }

            for rule in enabledRules where rule.matches(port) {
                let elapsedMinutes = now.timeIntervalSince(firstSeen) / 60.0
                guard elapsedMinutes >= Double(rule.timeoutMinutes) else { continue }

                if rule.notifyBeforeKill {
                    notificationService.notify(
                        title: "Auto-Kill: \(port.processName)",
                        body: "Port \(port.port) killed after \(rule.timeoutMinutes) min (rule: \(rule.name))"
                    )
                }

                kill(port)

                // Stop tracking so the rule doesn't re-trigger on the next scan.
                portFirstSeen.removeValue(forKey: key)
                break // Only the first matching rule applies.
            }
        }
    }

    private static func key(for port: PortInfo) -> String {
        "\(port.port)-\(port.pid)"
    }
}
