import Foundation
import Defaults

/// Service for sending webhook notifications on port events
@MainActor
final class WebhookService {
    static let shared = WebhookService()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private init() {}

    /// Sends a webhook for the given event and port info.
    /// Silently fails if no webhook URL is configured or the URL is invalid.
    func send(event: WebhookEvent, port: PortInfo) {
        let enabledEvents = Defaults[.webhookEvents]
        guard enabledEvents.contains(event) else { return }

        let urlString = Defaults[.webhookURL].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return }

        let payload = WebhookPayload.create(event: event, port: port)

        Task.detached { [encoder] in
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("PortKiller/\(AppInfo.versionString)", forHTTPHeaderField: "User-Agent")
                request.httpBody = try encoder.encode(payload)
                request.timeoutInterval = 10

                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("[Webhook] HTTP \(httpResponse.statusCode) for \(event.rawValue)")
                }
            } catch {
                print("[Webhook] Failed to send \(event.rawValue): \(error.localizedDescription)")
            }
        }
    }

    /// Sends webhooks for newly opened ports by comparing old and new port lists.
    func checkPortChanges(oldPorts: [PortInfo], newPorts: [PortInfo]) {
        let enabledEvents = Defaults[.webhookEvents]
        let urlString = Defaults[.webhookURL].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, !enabledEvents.isEmpty else { return }

        let oldSet = Set(oldPorts.map { "\($0.port)-\($0.pid)" })
        let newSet = Set(newPorts.map { "\($0.port)-\($0.pid)" })

        // Port opened events
        if enabledEvents.contains(.portOpened) {
            for port in newPorts {
                let key = "\(port.port)-\(port.pid)"
                if !oldSet.contains(key) {
                    send(event: .portOpened, port: port)
                }
            }
        }

        // Port closed events
        if enabledEvents.contains(.portClosed) {
            for port in oldPorts {
                let key = "\(port.port)-\(port.pid)"
                if !newSet.contains(key) {
                    send(event: .portClosed, port: port)
                }
            }
        }
    }

    /// Sends a test webhook with dummy data to verify the configuration.
    func sendTest() async -> Bool {
        let urlString = Defaults[.webhookURL].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return false }

        let payload = WebhookPayload(
            event: "test",
            port: 8080,
            process: "PortKiller",
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            timestamp: ISO8601DateFormatter().string(from: Date()),
            hostname: ProcessInfo.processInfo.hostName
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("PortKiller/\(AppInfo.versionString)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try encoder.encode(payload)
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
