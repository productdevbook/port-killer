import Foundation

/// A log entry from cloudflared tunnel output
@Observable
@MainActor
final class TunnelLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel

    nonisolated init(timestamp: Date = Date(), message: String, level: LogLevel = .info) {
        self.timestamp = timestamp
        self.message = message
        self.level = level
    }

    enum LogLevel: Sendable {
        case info
        case warning
        case error
        case request

        var color: String {
            switch self {
            case .info: "secondary"
            case .warning: "orange"
            case .error: "red"
            case .request: "blue"
            }
        }
    }

    /// Parses a cloudflared log line to determine level and clean message.
    nonisolated static func parse(_ line: String) -> TunnelLogEntry {
        let lowered = line.lowercased()

        let level: LogLevel
        if lowered.contains("error") || lowered.contains("failed") || lowered.contains("unable to") {
            level = .error
        } else if lowered.contains("warn") {
            level = .warning
        } else if lowered.contains("request") || lowered.contains("200") || lowered.contains("404") ||
                    lowered.contains("get ") || lowered.contains("post ") || lowered.contains("put ") ||
                    lowered.contains("delete ") || lowered.contains("status") {
            level = .request
        } else {
            level = .info
        }

        return TunnelLogEntry(message: line, level: level)
    }
}
