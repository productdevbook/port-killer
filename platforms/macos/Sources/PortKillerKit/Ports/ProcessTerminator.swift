public import Foundation
import Darwin

public struct TerminationError: Error, LocalizedError, Sendable {
    public enum Reason: Sendable, Equatable {
        case permissionDenied
        case failed(Int32)
    }

    public var pid: Int32
    public var reason: Reason

    public var errorDescription: String? {
        switch reason {
        case .permissionDenied:
            "Process \(pid) belongs to another user. Stop it from Terminal with sudo kill \(pid)."
        case .failed(let code):
            "Couldn't stop process \(pid): \(POSIXErrorCode(rawValue: code).map { POSIXError($0).localizedDescription } ?? "error \(code)")"
        }
    }
}

public enum ProcessTerminator {
    public static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    @concurrent
    public static func terminate(_ pid: Int32, force: Bool = false, grace: Duration = .milliseconds(600)) async throws(TerminationError) {
        guard pid > 0 else { return }
        if !force {
            try send(SIGTERM, to: pid)
            let deadline = ContinuousClock.now + grace
            while ContinuousClock.now < deadline {
                guard isRunning(pid) else { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        guard isRunning(pid) else { return }
        try send(SIGKILL, to: pid)
    }

    @concurrent
    public static func terminateTree(_ pid: Int32, force: Bool = false) async throws(TerminationError) {
        var order: [Int32] = []
        var queue = [pid]
        while let next = queue.popLast() {
            order.append(next)
            queue.append(contentsOf: PortScanner.childPIDs(of: next))
        }
        for member in order.reversed() {
            try await terminate(member, force: force)
        }
    }

    private static func send(_ signal: Int32, to pid: Int32) throws(TerminationError) {
        guard kill(pid, signal) != 0 else { return }
        switch errno {
        case ESRCH: return
        case EPERM: throw TerminationError(pid: pid, reason: .permissionDenied)
        case let code: throw TerminationError(pid: pid, reason: .failed(code))
        }
    }
}
