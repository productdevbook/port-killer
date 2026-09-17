public import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var error: String

    public var succeeded: Bool { status == 0 }

    public var combined: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CommandTimedOut: Error, Sendable {}

public enum CommandRunner {
    private static let outputLimit = 64 << 20

    @concurrent
    public static func run(
        _ executable: URL,
        _ arguments: [String],
        input: String? = nil,
        environment: [String: String] = [:],
        timeout: Duration? = nil
    ) async throws -> CommandResult {
        let environment = Self.environment(adding: environment)
        guard let timeout else {
            return try await collect(executable, arguments, input: input, environment: environment)
        }
        return try await withThrowingTaskGroup(of: CommandResult?.self) { group in
            group.addTask { try await collect(executable, arguments, input: input, environment: environment) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let first else { throw CommandTimedOut() }
            return first
        }
    }

    private static func collect(_ executable: URL, _ arguments: [String], input: String?, environment: Environment) async throws -> CommandResult {
        let result = if let input {
            try await Subprocess.run(
                .path(FilePath(executable.path)),
                arguments: Arguments(arguments),
                environment: environment,
                input: .string(input),
                output: .string(limit: outputLimit),
                error: .string(limit: outputLimit)
            )
        } else {
            try await Subprocess.run(
                .path(FilePath(executable.path)),
                arguments: Arguments(arguments),
                environment: environment,
                output: .string(limit: outputLimit),
                error: .string(limit: outputLimit)
            )
        }
        return CommandResult(status: status(result.terminationStatus), output: result.standardOutput, error: result.standardError)
    }

    @concurrent
    public static func stream(
        _ executable: URL,
        _ arguments: [String],
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
            environment: environment(adding: [:]),
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

    private static func environment(adding values: [String: String]) -> Environment {
        var changes: [Environment.Key: String?] = ["PATH": CommandLineTool.searchPath]
        for (name, value) in values {
            if let key = Environment.Key(rawValue: name) { changes[key] = value }
        }
        return .inherit.updating(changes)
    }
}
