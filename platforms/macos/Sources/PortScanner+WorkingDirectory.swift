/**
 * PortScanner+WorkingDirectory.swift
 * PortKiller
 *
 * Reads process working directories via proc_pidinfo. Like the sysctl-based
 * command lookup, this is a pure syscall per PID — no process spawns.
 */

import Foundation
import Darwin

extension PortScanner {
    /// Working directories for a set of PIDs (PIDs without access are omitted)
    nonisolated func workingDirectories(for pids: Set<Int>) -> [Int: String] {
        pids.reduce(into: [:]) { result, pid in
            result[pid] = Self.workingDirectory(for: pid)
        }
    }

    /// Reads a process's current working directory via proc_pidinfo(PROC_PIDVNODEPATHINFO).
    ///
    /// Returns nil for other users' processes (requires privileges) and for
    /// invalid PIDs — callers treat nil as "unknown".
    nonisolated static func workingDirectory(for pid: Int) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(Int32(pid), PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
