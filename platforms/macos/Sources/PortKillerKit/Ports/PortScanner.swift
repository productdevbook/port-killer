import Foundation
import OrderedCollections
import Synchronization
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum PortScanner {
    struct ListeningSocket {
        var pid: Int32
        var port: Int
        var address: String
    }

    private static let userNames = Mutex<[uid_t: String]>([:])

    @concurrent
    public static func scan(port: Int? = nil) async -> [ListeningPort] {
        listeningPorts(port: port)
    }

    public static func listeningPorts(port: Int? = nil) -> [ListeningPort] {
        struct Listener: Hashable {
            var port: Int
            var pid: Int32
        }
        var listeners: [Listener: OrderedSet<String>] = [:]
        for socket in listeningSockets(port: port) {
            listeners[Listener(port: socket.port, pid: socket.pid), default: []].append(socket.address)
        }
        var processes: [Int32: ProcessSnapshot] = [:]
        return listeners
            .map { listener, addresses in
                let process = processes[listener.pid] ?? snapshot(pid: listener.pid) ?? ProcessSnapshot(pid: listener.pid, name: "PID \(listener.pid)")
                processes[listener.pid] = process
                return ListeningPort(port: listener.port, addresses: Array(addresses), process: process)
            }
            .sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    @concurrent
    public static func isListening(port: Int) async -> Bool {
        hasListener(port: port)
    }

    @concurrent
    public static func establishedPIDs(port: Int) async -> Set<Int32> {
        connectedPIDs(port: port)
    }

    @concurrent
    public static func parent(of process: ProcessSnapshot) async -> ProcessSnapshot? {
        process.parentPID > 1 ? snapshot(pid: process.parentPID) : nil
    }

    public static func childrenByParent() -> [Int32: [Int32]] {
        var children: [Int32: [Int32]] = [:]
        for (pid, parent) in parentPIDs() {
            children[parent, default: []].append(pid)
        }
        return children
    }

    static func formatAddress(_ bytes: [UInt8]) -> String {
        let bytes = ipv4Mapped(bytes) ?? bytes
        guard bytes.contains(where: { $0 != 0 }) else { return "*" }
        guard bytes.count == 16 else { return bytes.map(String.init).joined(separator: ".") }
        let groups = stride(from: 0, to: 16, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        var longest: Range<Int>?
        var start: Int?
        for index in 0...groups.count {
            if index < groups.count, groups[index] == 0 {
                start = start ?? index
            } else if let runStart = start {
                if index - runStart > 1, index - runStart > longest?.count ?? 0 { longest = runStart..<index }
                start = nil
            }
        }
        let hex = groups.map { String($0, radix: 16) }
        guard let longest else { return "[\(hex.joined(separator: ":"))]" }
        let head = hex[..<longest.lowerBound].joined(separator: ":")
        let tail = hex[longest.upperBound...].joined(separator: ":")
        return "[\(head)::\(tail)]"
    }

    static func isLoopback(_ bytes: [UInt8]) -> Bool {
        let bytes = ipv4Mapped(bytes) ?? bytes
        if bytes.count == 4 { return bytes[0] == 127 }
        return bytes.count == 16 && bytes.dropLast().allSatisfy { $0 == 0 } && bytes[15] == 1
    }

    private static func ipv4Mapped(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count == 16, bytes[..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF else { return nil }
        return Array(bytes[12...])
    }

    static func userName(uid: uid_t) -> String {
        if let cached = userNames.withLock({ $0[uid] }) { return cached }
        var entry = unsafe passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        let name = buffer.withUnsafeMutableBufferPointer { pointer -> String? in
            guard let base = pointer.baseAddress,
                  unsafe getpwuid_r(uid, &entry, base, pointer.count, &result) == 0,
                  unsafe result != nil,
                  let raw = unsafe entry.pw_name
            else { return nil }
            return unsafe String(cString: raw)
        } ?? String(uid)
        userNames.withLock { $0[uid] = name }
        return name
    }
}
