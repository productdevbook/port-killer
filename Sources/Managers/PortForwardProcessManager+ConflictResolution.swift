import Foundation
import Darwin

extension PortForwardProcessManager {
    /// Kills any process using the specified port.
    func killProcessOnPort(_ port: Int) async {
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
                let pids = output.components(separatedBy: .newlines)
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
        } catch {
            // Ignore errors
        }
    }
}
