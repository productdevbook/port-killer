import Foundation
import Testing
@testable import PortKillerKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct PortScannerTests {
    @Test(arguments: [
        ([127, 0, 0, 1], "127.0.0.1"),
        ([0, 0, 0, 0], "*"),
        ([UInt8](repeating: 0, count: 16), "*"),
        ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], "[::1]"),
        ([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 192, 168, 1, 20], "192.168.1.20"),
        ([0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1], "[2001:db8:0:1::1]"),
        ([0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0x1C, 0x2B, 0, 0, 0, 0, 0, 1], "[fe80::1c2b:0:0:1]"),
        ([0x20, 0x01, 0x0D, 0xB8, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1], "[2001:db8:1:0:1:1:1:1]"),
    ] as [([UInt8], String)])
    func formatsAddresses(bytes: [UInt8], expected: String) {
        #expect(PortScanner.formatAddress(bytes) == expected)
    }

    @Test func detectsLoopbackAddresses() {
        #expect(PortScanner.isLoopback([127, 0, 0, 1]))
        #expect(PortScanner.isLoopback([127, 1, 2, 3]))
        #expect(!PortScanner.isLoopback([10, 0, 0, 1]))
        #expect(PortScanner.isLoopback([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]))
        #expect(PortScanner.isLoopback([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 127, 0, 0, 1]))
        #expect(!PortScanner.isLoopback([UInt8](repeating: 0, count: 16)))
    }

    @Test func parsesProcSocketTables() {
        let table = """
          sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
           0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 12345 1 0000000000000000 0
           1: 0100007F:1F90 0100007F:D2F0 01 00000000:00000000 00:00000000 00000000  1000        0 12346 1 0000000000000000 0
           2: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 999 1 0000000000000000 0
        """
        let sockets = ProcFileSystem.parseSockets(table)
        #expect(sockets.count == 3)
        #expect(sockets[0] == ProcFileSystem.Socket(
            inode: 12345,
            state: .listen,
            local: ProcFileSystem.Endpoint(address: [127, 0, 0, 1], port: 8080),
            remote: ProcFileSystem.Endpoint(address: [0, 0, 0, 0], port: 0)
        ))
        #expect(sockets[1].state == .established)
        #expect(sockets[1].remote.port == 54000)
        #expect(PortScanner.formatAddress(sockets[2].local.address) == "*")
        #expect(sockets[2].local.port == 22)
    }

    @Test func parsesIPv6SocketAddresses() throws {
        let loopback = try #require(ProcFileSystem.parseEndpoint("00000000000000000000000001000000:0BB8"))
        #expect(PortScanner.formatAddress(loopback.address) == "[::1]")
        #expect(loopback.port == 3000)
        let mapped = try #require(ProcFileSystem.parseEndpoint("0000000000000000FFFF00000100007F:0050"))
        #expect(PortScanner.formatAddress(mapped.address) == "127.0.0.1")
        #expect(ProcFileSystem.parseEndpoint("0100007F") == nil)
        #expect(ProcFileSystem.parseEndpoint("XYZ0007F:0050") == nil)
    }

    @Test func parsesProcessFiles() throws {
        let stat = "4242 (node (dev) server) S 17 4242 4242 0 -1 4194304 1 0 0 0 5 3 0 0 20 0 7 0 889900 1000 20 18446744073709551615"
        let parsed = try #require(ProcFileSystem.parseStat(stat))
        #expect(parsed.parentPID == 17)
        #expect(parsed.startTicks == 889900)
        #expect(ProcFileSystem.parseUID(status: "Name:\tnode\nPPid:\t17\nUid:\t1000\t1000\t1000\t1000\n") == 1000)
        #expect(ProcFileSystem.parseBootTime("cpu  1 2 3\nbtime 1758100000\nprocesses 5\n") == 1758100000)
        #expect(ProcFileSystem.parseCommandLine(Array("node\0server.js\0--port\03000\0".utf8)) == "node server.js --port 3000")
        #expect(ProcFileSystem.parseCommandLine([]) == nil)
        #expect(ProcFileSystem.socketInode("socket:[31337]") == 31337)
        #expect(ProcFileSystem.socketInode("pipe:[31337]") == nil)
    }

    @Test func findsItsOwnListener() async throws {
        let (descriptor, port) = try Self.openListener()
        defer { close(descriptor) }
        let pid = getpid()

        let listeners = PortScanner.listeningPorts(port: port)
        #expect(listeners.map(\.pid) == [pid])
        #expect(listeners.first?.addresses == ["127.0.0.1"])
        #expect(PortScanner.listeningPorts().contains { $0.port == port && $0.pid == pid })
        #expect(await PortScanner.isListening(port: port))

        let process = try #require(PortScanner.snapshot(pid: pid))
        #expect(!process.name.isEmpty)
        #expect(process.commandLine != nil)
        #expect(process.startDate != nil)
        #expect(PortScanner.childrenByParent()[process.parentPID]?.contains(pid) == true)
    }

    static func openListener() throws -> (descriptor: Int32, port: Int) {
        #if canImport(Darwin)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        #else
        let descriptor = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        try #require(descriptor >= 0)
        var address = sockaddr_in()
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe bind(descriptor, $0, length) }
        }
        try #require(bound == 0)
        try #require(listen(descriptor, 1) == 0)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            unsafe pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { unsafe getsockname(descriptor, $0, &length) }
        }
        try #require(named == 0)
        return (descriptor, Int(UInt16(bigEndian: address.sin_port)))
    }
}
