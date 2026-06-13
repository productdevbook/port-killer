import Foundation
import Darwin

extension PortForwardProcessManager {
    /// Kills any process using the specified port.
    func killProcessOnPort(_ port: Int) async {
        let output = await ProcessExecutor.output(
            "/usr/sbin/lsof",
            arguments: ["-ti", "tcp:\(port)"]
        ) ?? ""

        // Kill logic uses Darwin.kill (pure C) and await
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
