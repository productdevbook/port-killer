import Foundation

actor PortScanner {
    private let descriptionService = ProcessDescriptionService()

    /// Scan all listening TCP ports using lsof
    func scanPorts() async -> [PortInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            let commands = await getProcessCommands()
            return await parseLsofOutput(output, commands: commands)
        } catch {
            return []
        }
    }

    /// Get full command lines for processes using ps
    private func getProcessCommands() async -> [Int: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,command"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()

            // IMPORTANT: Read data BEFORE waitUntilExit to avoid deadlock
            // If pipe buffer fills up, ps will block waiting to write
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else {
                return [:]
            }

            var commands: [Int: String] = [:]
            let lines = output.components(separatedBy: .newlines)

            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }

                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count >= 2,
                      let pid = Int(parts[0]) else { continue }

                let fullCommand = String(parts[1])
                commands[pid] = fullCommand.count > 200 ? String(fullCommand.prefix(200)) + "..." : fullCommand
            }

            return commands
        } catch {
            return [:]
        }
    }

    /// Parse lsof output into PortInfo array
    private func parseLsofOutput(_ output: String, commands: [Int: String]) async -> [PortInfo] {
        var ports: [PortInfo] = []
        var seen: Set<String> = []
        let lines = output.components(separatedBy: .newlines)

        // Skip header line
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            // Parse: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // Example: node      34805 code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            // Process name (handle escaped names like "Code\x20H")
            var processName = String(components[0])
            // Decode escaped characters
            processName = processName
                .replacingOccurrences(of: "\\x20", with: " ")
                .replacingOccurrences(of: "\\x2f", with: "/")

            guard let pid = Int(components[1]) else { continue }

            // User name
            let user = String(components[2])

            // File descriptor
            let fd = String(components[3])

            // NAME is near the end, before (LISTEN)
            // Find the address:port part (second to last or contains ":")
            var addressPart = ""
            for i in stride(from: components.count - 1, through: 8, by: -1) {
                let comp = String(components[i])
                if comp.contains(":") && !comp.hasPrefix("0x") && !comp.hasPrefix("0t") {
                    addressPart = comp
                    break
                }
            }

            guard !addressPart.isEmpty else { continue }

            // Get full command from ps output
            let command = commands[pid] ?? processName

            guard let portInfo = await parseAddress(addressPart, processName: processName, pid: pid, user: user, command: command, fd: fd) else {
                continue
            }

            // Avoid duplicates (same port + pid) using O(1) Set lookup
            let key = "\(portInfo.port)-\(portInfo.pid)"
            if seen.insert(key).inserted {
                ports.append(portInfo)
            }
        }

        return ports.sorted { $0.port < $1.port }
    }

    /// Parse address string like "127.0.0.1:3000" or "*:8080"
    private func parseAddress(_ address: String, processName: String, pid: Int, user: String, command: String, fd: String) async -> PortInfo? {
        // Handle formats: "127.0.0.1:3000", "*:8080", "[::1]:3000"
        let parts: [String]

        if address.hasPrefix("[") {
            // IPv6: [::1]:3000
            guard let bracketEnd = address.firstIndex(of: "]") else { return nil }
            let afterBracket = address.index(after: bracketEnd)
            guard afterBracket < address.endIndex, address[afterBracket] == ":" else { return nil }
            let portStart = address.index(after: afterBracket)
            let addr = String(address[address.startIndex...bracketEnd])
            let port = String(address[portStart...])
            parts = [addr, port]
        } else {
            parts = address.components(separatedBy: ":")
        }

        guard parts.count >= 2,
              let port = Int(parts.last ?? "") else {
            return nil
        }

        let addr = parts.dropLast().joined(separator: ":")
        
        // Get process description
        let description = await descriptionService.getDescription(for: processName)

        return PortInfo.active(
            port: port,
            pid: pid,
            processName: processName,
            address: addr.isEmpty ? "*" : addr,
            user: user,
            command: command,
            fd: fd,
            description: description
        )
    }

    /// Kill a process by PID
    func killProcess(pid: Int, force: Bool = false) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = [force ? "-9" : "-15", String(pid)]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Kill process, try graceful first then force
    func killProcessGracefully(pid: Int) async -> Bool {
        // Try SIGTERM first
        let graceful = await killProcess(pid: pid, force: false)
        if graceful {
            // Wait a bit and check if process is gone
            try? await Task.sleep(for: .milliseconds(500))
        }

        // Force kill if still running
        return await killProcess(pid: pid, force: true)
    }
}
