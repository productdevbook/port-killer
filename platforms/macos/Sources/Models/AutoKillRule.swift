import Foundation
import Defaults

/// A rule that automatically kills processes matching certain criteria after a timeout.
struct AutoKillRule: Codable, Identifiable, Hashable, Sendable, Defaults.Serializable {
    var id: UUID
    /// Display name for the rule
    var name: String
    /// Process name pattern (supports * wildcard, e.g. "node*"). Empty means match any.
    var processPattern: String
    /// Specific port to match. 0 means match any port.
    var port: Int
    /// Minutes after which the process should be killed
    var timeoutMinutes: Int
    /// Whether to notify before killing
    var notifyBeforeKill: Bool
    /// Whether this rule is active
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        processPattern: String = "",
        port: Int = 0,
        timeoutMinutes: Int = 30,
        notifyBeforeKill: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.processPattern = processPattern
        self.port = port
        self.timeoutMinutes = timeoutMinutes
        self.notifyBeforeKill = notifyBeforeKill
        self.isEnabled = isEnabled
    }

    /// Checks if this rule matches a given port info.
    func matches(_ portInfo: PortInfo) -> Bool {
        // Check port match
        if port > 0 && portInfo.port != port { return false }

        // Check process pattern match
        if !processPattern.isEmpty {
            return matchesGlob(portInfo.processName, pattern: processPattern)
        }

        // At least one criterion must be specified
        return port > 0
    }

    /// Simple glob matching with * wildcard support.
    private func matchesGlob(_ string: String, pattern: String) -> Bool {
        let lowered = string.lowercased()
        let pat = pattern.lowercased()

        if !pat.contains("*") {
            return lowered == pat
        }

        let parts = pat.split(separator: "*", omittingEmptySubsequences: false).map(String.init)

        if parts.count == 1 { return lowered == pat }

        // Check prefix
        if let first = parts.first, !first.isEmpty, !lowered.hasPrefix(first) {
            return false
        }
        // Check suffix
        if let last = parts.last, !last.isEmpty, !lowered.hasSuffix(last) {
            return false
        }

        // Check all parts appear in order
        var searchStart = lowered.startIndex
        for part in parts where !part.isEmpty {
            guard let range = lowered.range(of: part, range: searchStart..<lowered.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }
}
