import Foundation
import FoundationModels
import Observation
import PortKillerKit

@Generable
struct ProcessExplanation: Equatable {
    @Generable
    enum Risk: Equatable {
        case safe
        case caution
        case avoid
    }

    @Guide(description: "What this process is and why it listens on the port, in one or two plain sentences.")
    var summary: String

    @Guide(description: "The app, tool or project the process most likely belongs to, in a few words.")
    var owner: String

    @Guide(description: "safe when stopping it only ends a local development server or helper that restarts on its own, caution when stopping it may interrupt work or another app, avoid when it belongs to macOS itself.")
    var risk: Risk

    @Guide(description: "One short sentence explaining the risk.")
    var reason: String
}

@Observable
final class ProcessExplainer {
    enum State: Equatable {
        case idle
        case working
        case explained(ProcessExplanation)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    private(set) var availability = SystemLanguageModel.default.availability

    func refreshAvailability() {
        let current = SystemLanguageModel.default.availability
        if current != availability { availability = current }
    }

    var unavailableReason: String? {
        switch availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This Mac doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in System Settings to explain processes."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    func state(for port: ListeningPort) -> State {
        states[key(port)] ?? .idle
    }

    func explain(_ port: ListeningPort, category: ProcessCategory, parentName: String?) async {
        let key = key(port)
        guard states[key] != .working else { return }
        states[key] = .working
        let session = LanguageModelSession(instructions: """
            You help software developers understand processes that listen on TCP ports on their Mac. \
            Be concrete and brief. Base the answer only on the facts given and on widely known software; say when you are unsure.
            """)
        let command = String(port.process.command.prefix(600))
        let prompt = """
            Process name: \(port.processName)
            Executable: \(port.process.executablePath ?? "unknown")
            Command line: \(command)
            Parent process: \(parentName ?? "unknown")
            User: \(port.process.user)
            Listening on TCP port \(port.port) at \(port.address)
            Category guess: \(category.rawValue)
            """
        do {
            let response = try await session.respond(to: prompt, generating: ProcessExplanation.self)
            states[key] = .explained(response.content)
        } catch {
            states[key] = .failed(error.localizedDescription)
        }
    }

    private func key(_ port: ListeningPort) -> String {
        "\(port.pid)-\(port.process.startDate?.timeIntervalSince1970 ?? 0)"
    }
}
