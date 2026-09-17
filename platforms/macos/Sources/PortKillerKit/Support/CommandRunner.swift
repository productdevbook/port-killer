public import Foundation
import Subprocess
import System

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var error: String

    public var succeeded: Bool { status == 0 }

    public var combined: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CommandError: Error, LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum CommandRunner {
    private static let outputLimit = 64 << 20

    @concurrent
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String] = [:]) async throws -> CommandResult {
        let result = try await Subprocess.run(
            .path(FilePath(executable.path)),
            arguments: Arguments(arguments),
            environment: .inherit.updating(environmentChanges(environment)),
            output: .string(limit: outputLimit),
            error: .string(limit: outputLimit)
        )
        return CommandResult(status: status(result.terminationStatus), output: result.standardOutput, error: result.standardError)
    }

    @concurrent
    public static func stream(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String] = [:],
        ownProcessGroup: Bool = false,
        onLine: @Sendable (String) async -> Void
    ) async throws -> Int32 {
        var options = PlatformOptions()
        options.createSession = ownProcessGroup
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: ownProcessGroup, allowedDurationToNextStep: .milliseconds(700)),
        ]
        let result = try await Subprocess.run(
            .path(FilePath(executable.path)),
            arguments: Arguments(arguments),
            environment: .inherit.updating(environmentChanges(environment)),
            platformOptions: options,
            input: .none,
            output: .sequence,
            error: .combinedWithOutput
        ) { execution in
            for try await line in execution.standardOutput.strings() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { await onLine(trimmed) }
            }
        }
        return status(result.terminationStatus)
    }

    static func status(_ termination: TerminationStatus) -> Int32 {
        switch termination {
        case .exited(let code): code
        case .signaled(let signal): 128 + signal
        }
    }

    static func environmentChanges(_ values: [String: String]) -> [Environment.Key: String?] {
        var changes: [Environment.Key: String?] = [:]
        for (name, value) in values {
            if let key = Environment.Key(rawValue: name) { changes[key] = value }
        }
        return changes
    }
}
