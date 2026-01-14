import Foundation

/// Parses output from kubectl and socat processes
enum PortForwardOutputParser {
    /// Checks if a log line indicates an error condition
    static func isErrorLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("error") ||
               lowercased.contains("failed") ||
               lowercased.contains("unable to") ||
               lowercased.contains("connection refused") ||
               lowercased.contains("lost connection") ||
               lowercased.contains("an error occurred")
    }

    /// Detects port conflict from log line and returns the conflicting port if found
    static func detectPortConflict(in line: String) -> Int? {
        let lowercased = line.lowercased()
        guard lowercased.contains("address already in use") else { return nil }

        // kubectl format: "listen tcp4 127.0.0.1:7700: bind: address already in use"
        if let portMatch = line.range(of: #"127\.0\.0\.1:(\d+)"#, options: .regularExpression) {
            let portStr = line[portMatch].split(separator: ":").last ?? ""
            return Int(portStr)
        }

        // socat format: "bind(5, {LEN=16 AF=2 0.0.0.0:7699}, 16): Address already in use"
        if let portMatch = line.range(of: #"0\.0\.0\.0:(\d+)"#, options: .regularExpression) {
            let portStr = line[portMatch].split(separator: ":").last ?? ""
            return Int(portStr)
        }

        return nil
    }
}
