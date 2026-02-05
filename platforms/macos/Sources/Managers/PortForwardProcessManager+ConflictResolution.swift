import Foundation
import Darwin

extension PortForwardProcessManager {
    /// Kills any process using the specified port.
    func killProcessOnPort(_ port: Int) async {
        // Wrap Process/Pipe lifecycle in autoreleasepool to release Obj-C bridged objects.
        // Read pipe data BEFORE waitUntilExit to avoid deadlock if output exceeds pipe buffer.
        let output: String = autoreleasepool {
            let lsof = Process()
            lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            lsof.arguments = ["-ti", "tcp:\(port)"]

            let pipe = Pipe()
            lsof.standardOutput = pipe
            lsof.standardError = FileHandle.nullDevice

            do {
                try lsof.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lsof.waitUntilExit()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                return ""
            }
        }

        // Kill logic uses Darwin.kill (pure C) and await, so stays outside the pool
        if !output.isEmpty {
            let pids = output.split(separator: "\n")
            for pidStr in pids {
                if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                    kill(pid, SIGTERM)
                }
            }

            try? await Task.sleep(for: .milliseconds(300))

            for pidStr in pids {
                if let pid = Int32(pidStr.trimmingCharacters(in: .whitespaces)) {
                    if kill(pid, 0) == 0 {
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
    }
}
