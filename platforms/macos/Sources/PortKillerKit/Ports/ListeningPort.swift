public import Foundation

public struct ProcessSnapshot: Sendable, Hashable {
    public var pid: Int32
    public var name: String
    public var executablePath: String?
    public var commandLine: String?
    public var user: String
    public var parentPID: Int32
    public var startDate: Date?

    public init(
        pid: Int32,
        name: String,
        executablePath: String? = nil,
        commandLine: String? = nil,
        user: String = "",
        parentPID: Int32 = 0,
        startDate: Date? = nil
    ) {
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.commandLine = commandLine
        self.user = user
        self.parentPID = parentPID
        self.startDate = startDate
    }

    public var command: String {
        commandLine ?? executablePath ?? name
    }

    public var appBundleURLs: [URL] {
        guard let executablePath else { return [] }
        var urls: [URL] = []
        var searchRange = executablePath.startIndex..<executablePath.endIndex
        while let range = executablePath.range(of: ".app/", range: searchRange) {
            urls.append(URL(filePath: String(executablePath[..<range.lowerBound]) + ".app"))
            searchRange = range.upperBound..<executablePath.endIndex
        }
        return urls.reversed()
    }
}

public struct ListeningPort: Sendable, Hashable, Identifiable {
    public var port: Int
    public var addresses: [String]
    public var process: ProcessSnapshot

    public init(port: Int, addresses: [String], process: ProcessSnapshot) {
        self.port = port
        self.addresses = addresses
        self.process = process
    }

    public var id: String { "\(port)-\(process.pid)" }
    public var pid: Int32 { process.pid }
    public var processName: String { process.name }
    public var address: String { addresses.joined(separator: ", ") }

    public var localURL: URL? {
        URL(string: "http://localhost:\(port)")
    }

    public var isLoopbackOnly: Bool {
        !addresses.isEmpty && addresses.allSatisfy { $0 == "127.0.0.1" || $0 == "[::1]" }
    }
}
