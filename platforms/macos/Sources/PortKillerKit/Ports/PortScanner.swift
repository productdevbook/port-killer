import Foundation
import Darwin
import Network
import OrderedCollections
import Synchronization

public enum PortScanner {
    struct TCPSocket {
        var state: Int32
        var localPort: Int
        var remotePort: Int
        var localAddress: String
    }

    private static let userNames = Mutex<[uid_t: String]>([:])

    @concurrent
    public static func scan() async -> [ListeningPort] {
        listeningPorts()
    }

    public static func listeningPorts() -> [ListeningPort] {
        struct Listener: Hashable {
            var port: Int
            var pid: Int32
        }
        var listeners: [Listener: OrderedSet<String>] = [:]
        for pid in allPIDs() {
            for socket in tcpSockets(pid: pid) where socket.state == TSI_S_LISTEN {
                listeners[Listener(port: socket.localPort, pid: pid), default: []].append(socket.localAddress)
            }
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
        allPIDs().contains { pid in
            tcpSockets(pid: pid).contains { $0.state == TSI_S_LISTEN && $0.localPort == port }
        }
    }

    @concurrent
    public static func establishedPIDs(port: Int) async -> Set<Int32> {
        var pids: Set<Int32> = []
        for pid in allPIDs() where tcpSockets(pid: pid).contains(where: { $0.state == TSI_S_ESTABLISHED && ($0.localPort == port || $0.remotePort == port) }) {
            pids.insert(pid)
        }
        return pids
    }

    public static func snapshot(pid: Int32) -> ProcessSnapshot? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = withUnsafeMutableBytes(of: &info) { unsafe proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0.baseAddress, size) }
        guard read == size else { return nil }
        let startSeconds = TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000
        return ProcessSnapshot(
            pid: pid,
            name: name(pid: pid) ?? "PID \(pid)",
            executablePath: executablePath(pid: pid),
            commandLine: commandLine(pid: pid),
            user: userName(uid: info.pbi_uid),
            parentPID: Int32(bitPattern: info.pbi_ppid),
            startDate: startSeconds > 0 ? Date(timeIntervalSince1970: startSeconds) : nil
        )
    }

    public static func childPIDs(of parent: Int32) -> [Int32] {
        allPIDs().filter { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let read = withUnsafeMutableBytes(of: &info) { unsafe proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0.baseAddress, size) }
            return read == size && Int32(bitPattern: info.pbi_ppid) == parent
        }
    }

    static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { unsafe proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(Int(max(count, 0))).filter { $0 > 0 }
    }

    static func tcpSockets(pid: Int32) -> [TCPSocket] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bufferSize) / stride + 8)
        let used = descriptors.withUnsafeMutableBytes { unsafe proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard used > 0 else { return [] }
        var sockets: [TCPSocket] = []
        for descriptor in descriptors.prefix(Int(used) / stride) where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            let read = withUnsafeMutableBytes(of: &info) {
                unsafe proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, $0.baseAddress, size)
            }
            guard read == size, info.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = unsafe info.psi.soi_proto.pri_tcp
            sockets.append(TCPSocket(
                state: tcp.tcpsi_state,
                localPort: port(tcp.tcpsi_ini.insi_lport),
                remotePort: port(tcp.tcpsi_ini.insi_fport),
                localAddress: localAddress(tcp.tcpsi_ini)
            ))
        }
        return sockets
    }

    private static func port(_ raw: Int32) -> Int {
        Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: raw)))
    }

    private static func localAddress(_ info: in_sockinfo) -> String {
        let flags = Int32(info.insi_vflag)
        if flags & INI_IPV4 != 0 {
            let bytes = unsafe withUnsafeBytes(of: info.insi_laddr.ina_46.i46a_addr4) { unsafe Data($0) }
            guard let address = IPv4Address(bytes), address != .any else { return "*" }
            return "\(address)"
        }
        let bytes = unsafe withUnsafeBytes(of: info.insi_laddr.ina_6) { unsafe Data($0) }
        guard let address = IPv6Address(bytes), address != .any else { return "*" }
        if let mapped = address.asIPv4 { return "\(mapped)" }
        return "[\(address)]"
    }

    private static func name(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = buffer.withUnsafeMutableBytes { unsafe proc_name(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { unsafe proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    static func commandLine(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard unsafe sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard unsafe sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcessArguments(Array(buffer.prefix(size)))
    }

    static func parseProcessArguments(_ buffer: [UInt8]) -> String? {
        guard buffer.count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.prefix(4).enumerated().reduce(Int32(0)) { $0 | Int32($1.element) << (8 * $1.offset) }
        guard argc > 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < buffer.count, arguments.count < min(Int(argc), 256) {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        let joined = arguments.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static func userName(uid: uid_t) -> String {
        if let cached = userNames.withLock({ $0[uid] }) { return cached }
        var entry = unsafe passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)
        let name = buffer.withUnsafeMutableBufferPointer { pointer -> String? in
            guard unsafe getpwuid_r(uid, &entry, pointer.baseAddress, pointer.count, &result) == 0, unsafe result != nil, let raw = unsafe entry.pw_name else { return nil }
            return unsafe String(cString: raw)
        } ?? String(uid)
        userNames.withLock { $0[uid] = name }
        return name
    }
}
