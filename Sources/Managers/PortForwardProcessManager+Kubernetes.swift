import Foundation

/// Thread-safe data accumulator for pipe output
private final class DataAccumulator: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
    }

    func getData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

extension PortForwardProcessManager {
    /// Fetches all Kubernetes namespaces.
    func fetchNamespaces() async throws -> [KubernetesNamespace] {
        let output = try await executeKubectl(arguments: ["get", "namespaces", "-o", "json", "--request-timeout=10s"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesNamespace.ListResponse.self,
                from: Data(output.utf8)
            )
            let namespaces = KubernetesNamespace.from(response: response)
            return namespaces.sorted { $0.name < $1.name }
        } catch {
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    /// Fetches services in a specific namespace.
    func fetchServices(namespace: String) async throws -> [KubernetesService] {
        let output = try await executeKubectl(arguments: ["get", "services", "-n", namespace, "-o", "json", "--request-timeout=10s"])

        do {
            let response = try JSONDecoder().decode(
                KubernetesService.ListResponse.self,
                from: Data(output.utf8)
            )
            let services = KubernetesService.from(response: response)
            return services.sorted { $0.name < $1.name }
        } catch {
            throw KubectlError.parsingFailed(error.localizedDescription)
        }
    }

    /// Executes a kubectl command and returns the output.
    /// Includes a 15 second timeout to prevent hanging.
    nonisolated func executeKubectl(arguments: [String]) async throws -> String {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: kubectlPath)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let outputAccumulator = DataAccumulator()
                let errorAccumulator = DataAccumulator()

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        outputAccumulator.append(data)
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        errorAccumulator.append(data)
                    }
                }

                do {
                    try process.run()

                    // Add timeout: kill process after 15 seconds
                    let timeoutWorkItem = DispatchWorkItem {
                        if process.isRunning {
                            process.terminate()
                        }
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeoutWorkItem)

                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    // Check if process was terminated due to timeout
                    if process.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: KubectlError.executionFailed("Command timed out"))
                        return
                    }

                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    outputAccumulator.append(remainingOutput)
                    errorAccumulator.append(remainingError)

                    let output = String(data: outputAccumulator.getData(), encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorAccumulator.getData(), encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        if errorOutput.contains("Unable to connect") ||
                           errorOutput.contains("connection refused") ||
                           errorOutput.contains("no configuration") ||
                           errorOutput.contains("dial tcp") {
                            continuation.resume(throwing: KubectlError.clusterNotConnected)
                        } else {
                            continuation.resume(throwing: KubectlError.executionFailed(
                                errorOutput.isEmpty ? "Unknown error" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                            ))
                        }
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
