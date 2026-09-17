import Foundation

enum ProcFileSystem {
    struct Endpoint: Hashable {
        var address: [UInt8]
        var port: Int
    }

    struct Socket: Hashable {
        enum State: Hashable {
            case listen
            case established
            case other
        }

        var inode: UInt64
        var state: State
        var local: Endpoint
        var remote: Endpoint
    }

    static func parseSockets(_ table: String) -> [Socket] {
        table.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 10,
                  let local = parseEndpoint(fields[1]),
                  let remote = parseEndpoint(fields[2]),
                  let state = UInt8(fields[3], radix: 16),
                  let inode = UInt64(fields[9])
            else { return nil }
            let socketState: Socket.State = switch state {
            case 0x0A: .listen
            case 0x01: .established
            default: .other
            }
            return Socket(inode: inode, state: socketState, local: local, remote: remote)
        }
    }

    static func parseEndpoint(_ text: Substring) -> Endpoint? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1], radix: 16), parts[0].count == 8 || parts[0].count == 32 else { return nil }
        let hex = Array(parts[0].utf8)
        var address: [UInt8] = []
        for word in stride(from: 0, to: hex.count, by: 8) {
            var bytes: [UInt8] = []
            for offset in stride(from: 0, to: 8, by: 2) {
                guard let byte = UInt8(String(decoding: hex[(word + offset)..<(word + offset + 2)], as: UTF8.self), radix: 16) else { return nil }
                bytes.append(byte)
            }
            address += bytes.reversed()
        }
        return Endpoint(address: address, port: port)
    }

    static func socketInode(_ linkTarget: String) -> UInt64? {
        guard linkTarget.hasPrefix("socket:["), linkTarget.hasSuffix("]") else { return nil }
        return UInt64(linkTarget.dropFirst("socket:[".count).dropLast())
    }

    static func parseStat(_ text: String) -> (parentPID: Int32, startTicks: UInt64)? {
        guard let close = text.lastIndex(of: ")") else { return nil }
        let fields = text[text.index(after: close)...].split(whereSeparator: \.isWhitespace)
        guard fields.count > 19, let parent = Int32(fields[1]), let start = UInt64(fields[19]) else { return nil }
        return (parent, start)
    }

    static func parseUID(status: String) -> UInt32? {
        status.split(separator: "\n")
            .first { $0.hasPrefix("Uid:") }
            .flatMap { $0.split(whereSeparator: \.isWhitespace).dropFirst().first }
            .flatMap { UInt32($0) }
    }

    static func parseBootTime(_ stat: String) -> Int? {
        stat.split(separator: "\n")
            .first { $0.hasPrefix("btime ") }
            .flatMap { Int($0.dropFirst("btime ".count)) }
    }

    static func parseCommandLine(_ bytes: [UInt8]) -> String? {
        let arguments = bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        let joined = arguments.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
