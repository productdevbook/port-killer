import Foundation

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

// MARK: - Callback Types

/// Callback for log output from port-forward processes
typealias LogHandler = @Sendable (String, PortForwardProcessType, Bool) -> Void

/// Callback for port conflict errors (address already in use)
typealias PortConflictHandler = @Sendable (Int) -> Void
