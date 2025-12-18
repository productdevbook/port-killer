import Foundation
import Darwin

// MARK: - Process Manager Actor

actor PortForwardProcessManager {
    // MARK: - Internal Properties (for extensions)

    var processes: [UUID: [PortForwardProcessType: Process]] = [:]
    var outputTasks: [UUID: [PortForwardProcessType: Task<Void, Never>]] = [:]
    var connectionErrors: [UUID: Date] = [:]
    var logHandlers: [UUID: LogHandler] = [:]
    var portConflictHandlers: [UUID: PortConflictHandler] = [:]

    // MARK: - Handler Management

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

    // MARK: - Output Reading

    func startReadingOutput(pipe: Pipe, id: UUID, type: PortForwardProcessType) {
        let task = Task { [weak self] in
            let handle = pipe.fileHandleForReading

            while true {
                let data = handle.availableData
                if data.isEmpty { break }

                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        let isError = PortForwardOutputParser.isErrorLine(line)

                        if isError {
                            await self?.markConnectionError(id: id)
                        }

                        if let port = PortForwardOutputParser.detectPortConflict(in: line) {
                            if let handler = await self?.portConflictHandlers[id] {
                                handler(port)
                            }
                        }

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

    // MARK: - Error Tracking

    func markConnectionError(id: UUID) {
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
        if let tasks = outputTasks[id] {
            for (_, task) in tasks {
                task.cancel()
            }
        }
        outputTasks[id] = nil

        guard let procs = processes[id] else { return }

        for (_, process) in procs {
            if process.isRunning {
                process.terminate()
            }
        }
        processes[id] = nil

        let scriptPath = "/tmp/pf-wrapper-\(id.uuidString).sh"
        try? FileManager.default.removeItem(atPath: scriptPath)
    }

    func isProcessRunning(for id: UUID, type: PortForwardProcessType) -> Bool {
        processes[id]?[type]?.isRunning ?? false
    }

    func isPortOpen(port: Int) -> Bool {
        PortHealthChecker.isPortOpen(port: port)
    }

    func killAllPortForwarderProcesses() async {
        let pkillKubectl = Process()
        pkillKubectl.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillKubectl.arguments = ["-9", "-f", "kubectl.*port-forward"]
        try? pkillKubectl.run()
        pkillKubectl.waitUntilExit()

        let pkillSocat = Process()
        pkillSocat.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkillSocat.arguments = ["-9", "-f", "socat.*TCP-LISTEN"]
        try? pkillSocat.run()
        pkillSocat.waitUntilExit()

        try? await Task.sleep(for: .milliseconds(500))

        processes.removeAll()
        for (_, tasks) in outputTasks {
            for (_, task) in tasks { task.cancel() }
        }
        outputTasks.removeAll()
    }
}
