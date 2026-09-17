#if canImport(Darwin)
import Darwin
import Foundation

extension PortScanner {
    struct TCPSocket {
        var state: Int32
        var info: in_sockinfo

        var localPort: Int { PortScanner.port(info.insi_lport) }
        var remotePort: Int { PortScanner.port(info.insi_fport) }

        var localAddress: [UInt8] {
            unsafe PortScanner.bytes(info.insi_vflag, v4: info.insi_laddr.ina_46.i46a_addr4, v6: info.insi_laddr.ina_6)
        }

        var remoteAddress: [UInt8] {
            unsafe PortScanner.bytes(info.insi_vflag, v4: info.insi_faddr.ina_46.i46a_addr4, v6: info.insi_faddr.ina_6)
        }
    }

    static func listeningSockets(port: Int?) -> [ListeningSocket] {
        var sockets: [ListeningSocket] = []
        for pid in allPIDs() {
            for socket in tcpSockets(pid: pid) where socket.state == TSI_S_LISTEN && (port == nil || socket.localPort == port) {
                sockets.append(ListeningSocket(pid: pid, port: socket.localPort, address: formatAddress(socket.localAddress)))
            }
        }
        return sockets
    }

    static func hasListener(port: Int) -> Bool {
        allPIDs().contains { pid in
            tcpSockets(pid: pid).contains { $0.state == TSI_S_LISTEN && $0.localPort == port }
        }
    }

    static func connectedPIDs(port: Int) -> Set<Int32> {
        var pids: Set<Int32> = []
        for pid in allPIDs() where tcpSockets(pid: pid).contains(where: { socket in
            socket.state == TSI_S_ESTABLISHED && (socket.localPort == port || (socket.remotePort == port && isLoopback(socket.remoteAddress)))
        }) {
            pids.insert(pid)
        }
        return pids
    }

    public static func snapshot(pid: Int32) -> ProcessSnapshot? {
        guard let info = bsdInfo(pid: pid) else { return nil }
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

    static func parentPIDs() -> [Int32: Int32] {
        var parents: [Int32: Int32] = [:]
        for pid in allPIDs() {
            if let info = bsdInfo(pid: pid) {
                parents[pid] = Int32(bitPattern: info.pbi_ppid)
            }
        }
        return parents
    }

    static func allPIDs() -> [Int32] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { unsafe proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(Int(max(count, 0))).filter { $0 > 0 }
    }

    private static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let read = withUnsafeMutableBytes(of: &info) { unsafe proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0.baseAddress, size) }
        return read == size ? info : nil
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
            sockets.append(TCPSocket(state: tcp.tcpsi_state, info: tcp.tcpsi_ini))
        }
        return sockets
    }

    private static func port(_ raw: Int32) -> Int {
        Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: raw)))
    }

    private static func bytes(_ flags: UInt8, v4: in_addr, v6: in6_addr) -> [UInt8] {
        if Int32(flags) & INI_IPV4 != 0 {
            return withUnsafeBytes(of: v4) { unsafe Array($0) }
        }
        return withUnsafeBytes(of: v6) { unsafe Array($0) }
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
        return parseProcessArguments(buffer.prefix(size))
    }

    static func parseProcessArguments(_ buffer: ArraySlice<UInt8>) -> String? {
        guard buffer.count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.prefix(4).enumerated().reduce(Int32(0)) { $0 | Int32($1.element) << (8 * $1.offset) }
        guard argc > 0 else { return nil }
        var index = buffer.startIndex + MemoryLayout<Int32>.size
        while index < buffer.endIndex, buffer[index] != 0 { index += 1 }
        while index < buffer.endIndex, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < buffer.endIndex, arguments.count < min(Int(argc), 256) {
            let start = index
            while index < buffer.endIndex, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        let joined = arguments.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
#endif
