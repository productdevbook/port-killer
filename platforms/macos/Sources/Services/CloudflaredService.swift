import Foundation
import Darwin
import Defaults

// MARK: - Cloudflared Service Actor

/// Manages cloudflared tunnel subprocesses
actor CloudflaredService {
    private var processes: [UUID: Process] = [:]
    private var outputTasks: [UUID: Task<Void, Never>] = [:]
    private var urlHandlers: [UUID: @Sendable (String) -> Void] = [:]
    private var errorHandlers: [UUID: @Sendable (String) -> Void] = [:]

    // MARK: - Dependency Check

    nonisolated var cloudflaredPath: String? {
        // Check custom path first
        if let custom = Defaults[.customCloudflaredPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        let paths = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated var isInstalled: Bool {
        cloudflaredPath != nil
    }

    nonisolated var isUsingCustomPath: Bool {
        if let custom = Defaults[.customCloudflaredPath],
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return true
        }
        return false
    }

    nonisolated var autoDetectedPath: String? {
        let paths = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared"
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Handler Management

    func setURLHandler(for id: UUID, handler: @escaping @Sendable (String) -> Void) {
        urlHandlers[id] = handler
    }

    func setErrorHandler(for id: UUID, handler: @escaping @Sendable (String) -> Void) {
        errorHandlers[id] = handler
    }

    func removeHandlers(for id: UUID) {
        urlHandlers.removeValue(forKey: id)
        errorHandlers.removeValue(forKey: id)
    }

    // MARK: - Tunnel Management

    func startTunnel(id: UUID, port: Int) throws -> Process {
        guard let cloudflaredPath = cloudflaredPath else {
            throw CloudflaredError.notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cloudflaredPath)
        let protocolValue = Defaults[.cloudflaredProtocol].rawValue
        process.arguments = ["tunnel", "--url", "localhost:\(port)", "--protocol", protocolValue]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        processes[id] = process

        startReadingOutput(pipe: pipe, id: id)

        return process
    }

    func stopTunnel(id: UUID) async {
        // Cancel output reading task
        outputTasks[id]?.cancel()
        outputTasks.removeValue(forKey: id)

        // Terminate process gracefully
        guard let process = processes[id] else { return }

        if process.isRunning {
            let pid = process.processIdentifier
            process.terminate()  // SIGTERM

            // Wait 500ms then force kill if still running
            try? await Task.sleep(for: .milliseconds(500))
            if kill(pid, 0) == 0 {  // Process still exists
                kill(pid, SIGKILL)
            }
        }

        processes.removeValue(forKey: id)
        removeHandlers(for: id)
    }

    func stopAllTunnels() async {
        for id in Array(processes.keys) {
            await stopTunnel(id: id)
        }
    }

    func isRunning(for id: UUID) -> Bool {
        processes[id]?.isRunning ?? false
    }

    // MARK: - Output Parsing

    private func startReadingOutput(pipe: Pipe, id: UUID) {
        let task = Task { [weak self] in
            let handle = pipe.fileHandleForReading

            while !Task.isCancelled {
                // Use autoreleasepool to prevent memory accumulation from FileHandle reads
                var output: String = ""
                autoreleasepool {
                    let data = handle.availableData
                    if data.isEmpty {
                        output = ""
                    } else {
                        output = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    }
                }

                if output.isEmpty { break }

                // Use split for zero-copy iteration
                let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
                for line in lines {
                    await self?.parseLine(String(line), for: id)
                }
            }
        }
        outputTasks[id] = task
    }

    private func parseLine(_ line: String, for id: UUID) {
        // cloudflared outputs the URL like:
        // "Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):
        // https://something-random.trycloudflare.com"
        // OR in newer versions with table format:
        // "| https://something-random.trycloudflare.com |"

        if let url = extractTunnelURL(from: line) {
            urlHandlers[id]?(url)
        }

        // Check for errors
        let lowercased = line.lowercased()
        if lowercased.contains("error") || lowercased.contains("failed") || lowercased.contains("unable to") {
            errorHandlers[id]?(line)
        }
    }

    private func extractTunnelURL(from line: String) -> String? {
        // Pattern: https://xxx.trycloudflare.com
        let pattern = #"https://[a-z0-9-]+\.trycloudflare\.com"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range])
        }
        return nil
    }
}

// MARK: - Errors

enum CloudflaredError: Error, LocalizedError, Sendable {
    case notInstalled
    case startFailed(String)
    case tunnelFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "cloudflared is not installed"
        case .startFailed(let message):
            return "Failed to start tunnel: \(message)"
        case .tunnelFailed(let message):
            return "Tunnel error: \(message)"
        }
    }
}
