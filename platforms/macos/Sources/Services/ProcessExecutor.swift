import Foundation

/// Result of running an external process.
struct ProcessResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }

    /// Standard output trimmed of surrounding whitespace and newlines.
    var trimmedOutput: String {
        standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Centralized launcher for external processes (`lsof`, `cloudflared`, `pkill`, `brew`, ...).
///
/// Every spawn in the app used to inline its own `Process`/`Pipe` boilerplate, each
/// re-deriving the same subtle invariants: wrap the lifecycle in `autoreleasepool` so the
/// Obj-C bridged objects don't accumulate across long-lived scanning tasks, and read the
/// pipe *before* `waitUntilExit()` to avoid deadlocking when output exceeds the pipe buffer.
/// `ProcessExecutor` is the single place that gets those right.
///
/// All work runs on a detached background task, so callers (including actors) never block
/// their executor on the synchronous `Process` API.
enum ProcessExecutor {

    /// Runs `executable` with `arguments`, capturing stdout and stderr.
    ///
    /// Returns `nil` only if the process could not be launched at all (e.g. the binary is
    /// missing). A non-zero exit code still yields a `ProcessResult` so callers can inspect
    /// `exitCode`/`standardError`.
    static func run(
        _ executable: String,
        arguments: [String],
        captureStandardError: Bool = true
    ) async -> ProcessResult? {
        await Task.detached(priority: .utility) {
            autoreleasepool {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                process.standardOutput = stdoutPipe

                let stderrPipe: Pipe?
                if captureStandardError {
                    let pipe = Pipe()
                    process.standardError = pipe
                    stderrPipe = pipe
                } else {
                    process.standardError = FileHandle.nullDevice
                    stderrPipe = nil
                }

                do {
                    try process.run()
                } catch {
                    return nil
                }

                // Read BEFORE waitUntilExit to avoid a deadlock when output exceeds the
                // pipe buffer (~64KB): the child blocks writing, we block waiting.
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
                process.waitUntilExit()

                return ProcessResult(
                    standardOutput: String(data: outData, encoding: .utf8) ?? "",
                    standardError: String(data: errData, encoding: .utf8) ?? "",
                    exitCode: process.terminationStatus
                )
            }
        }.value
    }

    /// Convenience: run a process and return its trimmed stdout, or `nil` on launch failure.
    /// stderr is discarded.
    static func output(_ executable: String, arguments: [String]) async -> String? {
        await run(executable, arguments: arguments, captureStandardError: false)?.trimmedOutput
    }

    /// Fire-and-forget launch (e.g. `pkill`). Discards all output and ignores failures.
    static func runDiscardingOutput(_ executable: String, arguments: [String]) async {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }.value
    }
}
