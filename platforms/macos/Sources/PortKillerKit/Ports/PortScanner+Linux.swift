#if os(Linux)
import Foundation
import Glibc

extension PortScanner {
    static func listeningSockets(port: Int?) -> [ListeningSocket] {
        let sockets = readSockets().filter { $0.state == .listen && (port == nil || $0.local.port == port) }
        guard !sockets.isEmpty else { return [] }
        let owners = socketOwners(Set(sockets.map(\.inode)))
        return sockets.flatMap { socket in
            (owners[socket.inode] ?? []).map { ListeningSocket(pid: $0, port: socket.local.port, address: formatAddress(socket.local.address)) }
        }
    }

    static func hasListener(port: Int) -> Bool {
        readSockets().contains { $0.state == .listen && $0.local.port == port }
    }

    static func connectedPIDs(port: Int) -> Set<Int32> {
        let sockets = readSockets().filter { socket in
            socket.state == .established && (socket.local.port == port || (socket.remote.port == port && isLoopback(socket.remote.address)))
        }
        guard !sockets.isEmpty else { return [] }
        return Set(socketOwners(Set(sockets.map(\.inode))).values.joined())
    }

    public static func snapshot(pid: Int32) -> ProcessSnapshot? {
        guard let stat = read("/proc/\(pid)/stat"), let parsed = ProcFileSystem.parseStat(stat) else { return nil }
        let name = read("/proc/\(pid)/comm")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let arguments = (try? Data(contentsOf: URL(filePath: "/proc/\(pid)/cmdline"))).flatMap { ProcFileSystem.parseCommandLine(Array($0)) }
        let uid = read("/proc/\(pid)/status").flatMap(ProcFileSystem.parseUID)
        let bootTime = read("/proc/stat").flatMap(ProcFileSystem.parseBootTime)
        let ticks = sysconf(Int32(_SC_CLK_TCK))
        return ProcessSnapshot(
            pid: pid,
            name: name.flatMap { $0.isEmpty ? nil : $0 } ?? "PID \(pid)",
            executablePath: try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(pid)/exe"),
            commandLine: arguments,
            user: uid.map(userName) ?? "",
            parentPID: parsed.parentPID,
            startDate: bootTime.flatMap { boot in
                ticks > 0 ? Date(timeIntervalSince1970: TimeInterval(boot) + TimeInterval(parsed.startTicks) / TimeInterval(ticks)) : nil
            }
        )
    }

    static func parentPIDs() -> [Int32: Int32] {
        var parents: [Int32: Int32] = [:]
        for pid in processIDs() {
            if let stat = read("/proc/\(pid)/stat"), let parsed = ProcFileSystem.parseStat(stat) {
                parents[pid] = parsed.parentPID
            }
        }
        return parents
    }

    private static func readSockets() -> [ProcFileSystem.Socket] {
        ["/proc/net/tcp", "/proc/net/tcp6"].flatMap { path in
            read(path).map(ProcFileSystem.parseSockets) ?? []
        }
    }

    private static func socketOwners(_ inodes: Set<UInt64>) -> [UInt64: [Int32]] {
        var owners: [UInt64: [Int32]] = [:]
        for pid in processIDs() {
            let directory = "/proc/\(pid)/fd"
            for descriptor in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "\(directory)/\(descriptor)"),
                      let inode = ProcFileSystem.socketInode(target),
                      inodes.contains(inode)
                else { continue }
                owners[inode, default: []].append(pid)
            }
        }
        return owners
    }

    private static func processIDs() -> [Int32] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/proc")) ?? []).compactMap(Int32.init)
    }

    private static func read(_ path: String) -> String? {
        (try? Data(contentsOf: URL(filePath: path))).map { String(decoding: $0, as: UTF8.self) }
    }
}
#endif
