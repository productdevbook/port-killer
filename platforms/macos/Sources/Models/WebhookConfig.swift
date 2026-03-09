import Foundation
import Defaults

/// Events that can trigger webhook notifications
enum WebhookEvent: String, CaseIterable, Codable, Sendable, Defaults.Serializable {
    case portOpened = "port_opened"
    case portClosed = "port_closed"
    case portKilled = "port_killed"

    var displayName: String {
        switch self {
        case .portOpened: "Port Opened"
        case .portClosed: "Port Closed"
        case .portKilled: "Port Killed"
        }
    }
}

/// Webhook payload sent to the configured URL
struct WebhookPayload: Codable, Sendable {
    let event: String
    let port: Int
    let process: String
    let pid: Int
    let timestamp: String
    let hostname: String

    static func create(event: WebhookEvent, port: PortInfo) -> WebhookPayload {
        WebhookPayload(
            event: event.rawValue,
            port: port.port,
            process: port.processName,
            pid: port.pid,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            hostname: ProcessInfo.processInfo.hostName
        )
    }
}
