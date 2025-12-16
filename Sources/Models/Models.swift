import Foundation

struct PortInfo: Identifiable, Hashable, Sendable {
    let id = UUID()
    let port: Int
    let pid: Int
    let processName: String
    let address: String

    var displayPort: String { ":\(port)" }
}

struct WatchedPort: Identifiable, Codable {
    let id: UUID
    let port: Int
    var notifyOnStart: Bool
    var notifyOnStop: Bool

    init(port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = UUID()
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }
}
