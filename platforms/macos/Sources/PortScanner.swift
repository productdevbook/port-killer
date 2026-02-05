import Foundation

/**
 * PortScanner is a Swift actor that safely scans system ports and manages process termination.
 *
 * This actor provides thread-safe port scanning and process killing operations.
 * It uses system commands (lsof, ps, kill) to interact with the operating system.
 *
 * Key responsibilities:
 * - Scan all listening TCP ports using lsof
 * - Retrieve full command information for processes using ps
 * - Kill processes gracefully (SIGTERM then SIGKILL)
 * - Parse lsof output into structured PortInfo objects
 *
 * Thread Safety:
 * This is an actor, so all methods are isolated and can be called safely from any context.
 */
actor PortScanner: PortScannerProtocol {

    /**
     * Scans all listening TCP ports using lsof.
     *
     * Executes: `lsof -iTCP -sTCP:LISTEN -P -n +c 0`
     *
     * Flags explained:
     * - -iTCP: Show only TCP connections
     * - -sTCP:LISTEN: Show only listening sockets
     * - -P: Show port numbers (don't resolve to service names)
     * - -n: Show IP addresses (don't resolve to hostnames)
     * - +c 0: Show full command name (unlimited length)
     *
     * @returns Array of PortInfo objects representing all listening ports
     */
    func scanPorts() async -> [PortInfo] {
        // Wrap entire Process/Pipe lifecycle in autoreleasepool to release Obj-C bridged
        // objects (Process, Pipe, FileHandle, URL, Data) immediately after each scan.
        // Without this, these objects accumulate across the long-lived scanning Task,
        // causing ~35KB per scan × 47,520 scans over 66 hours = ~1.7GB leak.
        let output: String = autoreleasepool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()

                // CRITICAL: Read data BEFORE waitUntilExit to avoid deadlock.
                // If lsof output exceeds the pipe buffer (~64KB), lsof blocks waiting
                // to write. If we waitUntilExit first, we deadlock.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                print("[PortScanner] Failed to scan ports: \(error.localizedDescription)")
                return ""
            }
        }

        guard !output.isEmpty else { return [] }

        let commands = await getProcessCommands()
        return parseLsofOutput(output, commands: commands)
    }

    /**
     * Retrieves full command line information for all processes.
     *
     * Executes: `ps -axo pid,command`
     *
     * This provides more detailed command information than lsof alone.
     *
     * @returns Dictionary mapping PID to full command string
     */
    private func getProcessCommands() async -> [Int: String] {
        // Wrap Process/Pipe lifecycle in autoreleasepool; parsing stays outside
        let output: String = autoreleasepool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "pid,command"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()

                // CRITICAL: Read data BEFORE waitUntilExit to avoid deadlock.
                // If the pipe buffer fills up (common with large process lists),
                // ps blocks waiting to write. waitUntilExit first = deadlock.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                print("[PortScanner] Failed to get process commands: \(error.localizedDescription)")
                return ""
            }
        }

        guard !output.isEmpty else { return [:] }

        var commands: [Int: String] = [:]
        // Use split for zero-copy Substring iteration
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines.dropFirst() {
            // Trim whitespace using Substring operations
            let trimmed = line.drop(while: { $0.isWhitespace })
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int(parts[0]) else { continue }

            let fullCommand = String(parts[1])
            commands[pid] = fullCommand
        }

        return commands
    }

    /**
     * Parses lsof command output into structured PortInfo objects.
     *
     * Expected lsof output format:
     * ```
     * COMMAND    PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
     * node     34805  code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
     * ```
     *
     * This method:
     * 1. Skips the header line
     * 2. Parses each line to extract process and port information
     * 3. Handles escaped characters in process names (e.g., "Code\x20H" → "Code H")
     * 4. Merges with command information from ps
     * 5. Deduplicates entries (same port + PID)
     *
     * @param output - Raw string output from lsof command
     * @param commands - Dictionary of PID to full command string from ps
     * @returns Array of unique PortInfo objects, sorted by port number
     */
    nonisolated private func parseLsofOutput(_ output: String, commands: [Int: String]) -> [PortInfo] {
        var ports: [PortInfo] = []
        var seen: Set<String> = []
        // Use split for zero-copy Substring iteration (no allocation per line)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        // Skip header line and process each data line
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }

            // Parse lsof output columns:
            // COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // Example: node      34805 code   19u  IPv6 0x3d8015e195af1f3f      0t0  TCP [::1]:3000 (LISTEN)
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            // Extract process name and handle escaped characters
            // lsof escapes special characters: "Code Helper" → "Code\x20Helper"
            var processName = String(components[0])
            processName = processName
                .replacingOccurrences(of: "\\x20", with: " ")  // Space
                .replacingOccurrences(of: "\\x2f", with: "/")  // Slash

            guard let pid = Int(components[1]) else { continue }

            // User name - use Substring directly where possible
            let user = String(components[2])

            // File descriptor
            let fd = String(components[3])

            // Extract the NAME column (address:port)
            // It's usually the second-to-last column, before "(LISTEN)"
            // Format: "127.0.0.1:3000", "*:8080", or "[::1]:3000"
            // We search backwards to find a component with ":" that isn't a device ID
            var addressPart: Substring = ""
            for i in stride(from: components.count - 1, through: 8, by: -1) {
                let comp = components[i]
                // Skip device IDs (0x...) and sizes (0t...)
                if comp.contains(":") && !comp.hasPrefix("0x") && !comp.hasPrefix("0t") {
                    addressPart = comp
                    break
                }
            }

            guard !addressPart.isEmpty else { continue }

            // Get full command from ps output
            let command = commands[pid] ?? processName

            guard let portInfo = parseAddress(String(addressPart), processName: processName, pid: pid, user: user, command: command, fd: fd) else {
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

    /**
     * Parses an address:port string into a PortInfo object.
     *
     * Handles multiple address formats:
     * - IPv4: "127.0.0.1:3000" or "*:8080"
     * - IPv6: "[::1]:3000" or "[fe80::1]:8080"
     *
     * @param address - The address:port string to parse
     * @param processName - Name of the process using the port
     * @param pid - Process ID
     * @param user - User running the process
     * @param command - Full command line of the process
     * @param fd - File descriptor number
     * @returns PortInfo object or nil if parsing fails
     */
    nonisolated private func parseAddress(_ address: String, processName: String, pid: Int, user: String, command: String, fd: String) -> PortInfo? {
        let parts: [String]

        if address.hasPrefix("[") {
            // IPv6 format: [::1]:3000
            // Split on the closing bracket to separate address from port
            guard let bracketEnd = address.firstIndex(of: "]") else { return nil }
            let afterBracket = address.index(after: bracketEnd)
            guard afterBracket < address.endIndex, address[afterBracket] == ":" else { return nil }
            let portStart = address.index(after: afterBracket)
            let addr = String(address[address.startIndex...bracketEnd])
            let port = String(address[portStart...])
            parts = [addr, port]
        } else {
            // IPv4 format: 127.0.0.1:3000 or *:8080
            parts = address.components(separatedBy: ":")
        }

        guard parts.count >= 2,
              let port = Int(parts.last ?? "") else {
            return nil
        }

        let addr = parts.dropLast().joined(separator: ":")

        return PortInfo.active(
            port: port,
            pid: pid,
            processName: processName,
            address: addr.isEmpty ? "*" : addr,
            user: user,
            command: command,
            fd: fd
        )
    }

    /**
     * Kills a process by sending a termination signal.
     *
     * Executes: `kill -15 <PID>` (SIGTERM) or `kill -9 <PID>` (SIGKILL)
     *
     * @param pid - The process ID to kill
     * @param force - If true, sends SIGKILL (-9) instead of SIGTERM (-15)
     * @returns True if the kill command executed successfully (exit code 0)
     */
    func killProcess(pid: Int, force: Bool = false) async -> Bool {
        autoreleasepool {
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
    }

    /**
     * Attempts to kill a process gracefully, falling back to force kill if needed.
     *
     * Strategy:
     * 1. Send SIGTERM (graceful shutdown signal)
     * 2. Wait 500ms for process to clean up
     * 3. Send SIGKILL (immediate termination)
     *
     * This two-stage approach allows processes to:
     * - Close file handles properly
     * - Flush buffers to disk
     * - Send shutdown notifications
     * - Clean up temporary resources
     *
     * @param pid - The process ID to kill
     * @returns True if either kill command succeeded
     */
    func killProcessGracefully(pid: Int) async -> Bool {
        // Try SIGTERM first (allows graceful shutdown)
        let graceful = await killProcess(pid: pid, force: false)
        if graceful {
            // Give the process time to clean up (500ms grace period)
            try? await Task.sleep(for: .milliseconds(500))
        }

        // Force kill with SIGKILL (immediate termination)
        return await killProcess(pid: pid, force: true)
    }
}
