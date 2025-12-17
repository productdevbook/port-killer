import Foundation
import Darwin

// MARK: - Process Types

enum PortForwardProcessType: String, Sendable {
    case portForward = "kubectl"
    case proxy = "socat"
}

// MARK: - Errors

enum KubectlError: Error, LocalizedError, Sendable {
    case kubectlNotFound
    case executionFailed(String)
    case parsingFailed(String)
    case clusterNotConnected

    var errorDescription: String? {
        switch self {
        case .kubectlNotFound:
            return "kubectl not found. Please install kubernetes-cli."
        case .executionFailed(let message):
            return "kubectl failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        case .clusterNotConnected:
            return "Cannot connect to Kubernetes cluster. Check your kubectl configuration."
        }
    }
}

// MARK: - Process Manager Actor

/// Callback for log output from port-forward processes
typealias LogHandler = @Sendable (String, PortForwardProcessType, Bool) -> Void

/// Callback for port conflict errors (address already in use)
typealias PortConflictHandler = @Sendable (Int) -> Void

actor PortForwardProcessManager {
    private var processes: [UUID: [PortForwardProcessType: Process]] = [:]
    private var outputTasks: [UUID: [PortForwardProcessType: Task<Void, Never>]] = [:]
    private var connectionErrors: [UUID: Date] = [:]
    private var logHandlers: [UUID: LogHandler] = [:]
    private var portConflictHandlers: [UUID: PortConflictHandler] = [:]

    func setLogHandler(for id: UUID, handler: @escaping LogHandler) {
        logHandlers[id] = handler
    }

    func removeLogHandler(for id: UUID) {
        logHandlers.removeValue(forKey: id)
    }

    func setPortConflictHandler(for id: UUID, handler: @escaping PortConflictHandler) {
        portConflictHandlers[id] = handler
    }

    func removePortConflictHandler(for id: UUID) {
        portConflictHandlers.removeValue(forKey: id)
    }

    // MARK: - Port Forward

    func startPortForward(
        id: UUID,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int
    ) async throws -> Process {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = [
            "port-forward",
            "-n", namespace,
            "svc/\(service)",
            "\(localPort):\(remotePort)",
            "--address=127.0.0.1"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.portForward] = process

        startReadingOutput(pipe: pipe, id: id, type: .portForward)

        return process
    }

    // MARK: - Standard Proxy

    /// Standard proxy mode: socat connects to already-running kubectl port-forward
    func startProxy(
        id: UUID,
        externalPort: Int,
        internalPort: Int
    ) async throws -> Process {
        guard let socatPath = DependencyChecker.shared.socatPath else {
            throw KubectlError.executionFailed("socat not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: socatPath)
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "TCP:127.0.0.1:\(internalPort)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    // MARK: - Direct Exec Proxy (Multi-Connection)

    /// Multi-connection proxy: socat spawns new kubectl port-forward for each connection
    func startDirectExecProxy(
        id: UUID,
        namespace: String,
        service: String,
        externalPort: Int,
        remotePort: Int
    ) async throws -> Process {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        guard let socatPath = DependencyChecker.shared.socatPath else {
            throw KubectlError.executionFailed("socat not found for multi-connection mode")
        }

        // Create wrapper script - runs for each connection
        let wrapperScript = """
            #!/bin/bash
            # Calculate unique port (30000-60000 range)
            PORT=$((30000 + ($$ % 30000)))

            # Find another port if already in use
            while /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; do
                PORT=$((PORT + 1))
            done

            # Start kubectl port-forward
            \(kubectlPath) port-forward -n \(namespace) svc/\(service) $PORT:\(remotePort) --address=127.0.0.1 >/dev/null 2>&1 &
            KPID=$!

            # Cleanup trap
            trap "kill $KPID 2>/dev/null" EXIT

            # Wait for port to open (max 5 seconds)
            for i in 1 2 3 4 5 6 7 8 9 10; do
                if /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; then
                    break
                fi
                sleep 0.5
            done

            # Connect stdin/stdout to TCP using socat
            \(socatPath) - TCP:127.0.0.1:$PORT
            """

        // Write script to temporary file
        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try wrapperScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: socatPath)
        process.arguments = [
            "TCP-LISTEN:\(externalPort),fork,reuseaddr",
            "EXEC:\(scriptPath)"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw error
        }

        if processes[id] == nil {
            processes[id] = [:]
        }
        processes[id]?[.proxy] = process

        startReadingOutput(pipe: pipe, id: id, type: .proxy)

        return process
    }

    // MARK: - Output Reading

    private func startReadingOutput(pipe: Pipe, id: UUID, type: PortForwardProcessType) {
        let task = Task { [weak self] in
            let handle = pipe.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty { break }

                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        let lowercased = line.lowercased()
                        let isError = lowercased.contains("error") ||
                                      lowercased.contains("failed") ||
                                      lowercased.contains("unable to") ||
                                      lowercased.contains("connection refused") ||
                                      lowercased.contains("lost connection") ||
                                      lowercased.contains("an error occurred")

                        if isError {
                            await self?.markConnectionError(id: id)
                        }

                        // Detect port conflict: "address already in use"
                        if lowercased.contains("address already in use") {
                            var detectedPort: Int?

                            // kubectl format: "listen tcp4 127.0.0.1:7700: bind: address already in use"
                            if let portMatch = line.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) {
                                let portStr = line[portMatch].split(separator: ":").last ?? ""
                                detectedPort = Int(portStr)
                            }
                            // socat format: "bind(5, {LEN=16 AF=2 0.0.0.0:7699}, 16): Address already in use"
                            else if let portMatch = line.range(of: #"0\.0\.0\.0:(\d+)"#, options: .regularExpression) {
                                let portStr = line[portMatch].split(separator: ":").last ?? ""
                                detectedPort = Int(portStr)
                            }

                            if let port = detectedPort {
                                if let handler = await self?.portConflictHandlers[id] {
                                    handler(port)
                                }
                            }
                        }

                        // Send log to handler
                        if let handler = await self?.logHandlers[id] {
                            handler(line, type, isError)
                        }
                    }
                }
            }
        }

        if outputTasks[id] == nil {
            outputTasks[id] = [:]
        }
        outputTasks[id]?[type] = task
    }

    // MARK: - Port Conflict Resolution

    /// Kill any process listening on the specified port
    func killProcessOnPort(_ port: Int) async {
        // Use lsof to find PID listening on the port
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:\(port)"]

        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice

        do {
            try lsof.run()
            lsof.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                // Kill each PID found
                let pids = output.components(separatedBy: .newlines)
                for pidStr in pids {
                    if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                        // SIGTERM first
                        kill(pid, SIGTERM)
                    }
                }

                // Wait a bit then force kill if needed
                try? await Task.sleep(for: .milliseconds(300))

                for pidStr in pids {
                    if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                        // Check if still running, then SIGKILL
                        if kill(pid, 0) == 0 {
                            kill(pid, SIGKILL)
                        }
                    }
                }
            }
        } catch {
            // Ignore errors
        }
    }

    // MARK: - Error Tracking

    private func markConnectionError(id: UUID) {
        connectionErrors[id] = Date()
    }

    func hasRecentError(for id: UUID, within seconds: TimeInterval = 10) -> Bool {
        guard let errorTime = connectionErrors[id] else { return false }
        return Date().timeIntervalSince(errorTime) < seconds
    }

    func clearError(for id: UUID) {
        connectionErrors.removeValue(forKey: id)
    }

    // MARK: - Process Lifecycle

    func killProcesses(for id: UUID) {
        // Cancel output reading tasks
        if let tasks = outputTasks[id] {
            for (_, task) in tasks {
                task.cancel()
            }
        }
        outputTasks[id] = nil

        // Kill processes
        guard let procs = processes[id] else { return }

        for (_, process) in procs {
            if process.isRunning {
                process.terminate()
            }
        }
        processes[id] = nil

        // Cleanup temp wrapper script
        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try? FileManager.default.removeItem(atPath: scriptPath)
    }

    func isProcessRunning(for id: UUID, type: PortForwardProcessType) -> Bool {
        processes[id]?[type]?.isRunning ?? false
    }

    /// Check if a port is actually accepting connections (TCP health check)
    func isPortOpen(port: Int) -> Bool {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    func killAllPortForwarderProcesses() async {
        // pkill kubectl port-forward
        let pkillKubectl = Process()
        pkillKubectl.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillKubectl.arguments = ["-9", "-f", "kubectl.*port-forward"]
        try? pkillKubectl.run()
        pkillKubectl.waitUntilExit()

        // pkill socat TCP-LISTEN
        let pkillSocat = Process()
        pkillSocat.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillSocat.arguments = ["-9", "-f", "socat.*TCP-LISTEN"]
        try? pkillSocat.run()
        pkillSocat.waitUntilExit()

        // Wait for ports to be freed
        try? await Task.sleep(for: .milliseconds(500))

        // Clear internal tracking
        processes.removeAll()
        for (_, tasks) in outputTasks {
            for (_, task) in tasks { task.cancel() }
        }
        outputTasks.removeAll()
    }

    // MARK: - Kubernetes Discovery

    func fetchNamespaces() async throws -> [KubernetesNamespace] {
        let output = try await executeKubectl(arguments: ["get", "namespaces", "-o", "json"])

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

    func fetchServices(namespace: String) async throws -> [KubernetesService] {
        let output = try await executeKubectl(arguments: ["get", "services", "-n", namespace, "-o", "json"])

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

    private func executeKubectl(arguments: [String]) async throws -> String {
        guard let kubectlPath = DependencyChecker.shared.kubectlPath else {
            throw KubectlError.kubectlNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectlPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                if errorOutput.contains("Unable to connect") ||
                   errorOutput.contains("connection refused") ||
                   errorOutput.contains("no configuration") ||
                   errorOutput.contains("dial tcp") {
                    throw KubectlError.clusterNotConnected
                }
                throw KubectlError.executionFailed(errorOutput.isEmpty ? "Unknown error" : errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            return output
        } catch let error as KubectlError {
            throw error
        } catch {
            throw KubectlError.executionFailed(error.localizedDescription)
        }
    }
}
