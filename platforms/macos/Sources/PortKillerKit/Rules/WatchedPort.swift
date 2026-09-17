public import Foundation

public struct WatchedPort: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var port: Int
    public var notifyOnStart: Bool
    public var notifyOnStop: Bool

    public init(id: UUID = UUID(), port: Int, notifyOnStart: Bool = true, notifyOnStop: Bool = true) {
        self.id = id
        self.port = port
        self.notifyOnStart = notifyOnStart
        self.notifyOnStop = notifyOnStop
    }
}

public struct WatchMonitor: Sendable {
    public enum Event: Sendable, Hashable {
        case started(port: Int, processName: String)
        case stopped(port: Int)
    }

    private var previous: [Int: Bool] = [:]

    public init() {}

    public mutating func events(watched: [WatchedPort], ports: [ListeningPort]) -> [Event] {
        let active = Dictionary(ports.map { ($0.port, $0.processName) }, uniquingKeysWith: { first, _ in first })
        previous = previous.filter { entry in watched.contains { $0.port == entry.key } }
        var events: [Event] = []
        for watch in watched {
            let isActive = active[watch.port] != nil
            if let wasActive = previous[watch.port] {
                if wasActive, !isActive, watch.notifyOnStop {
                    events.append(.stopped(port: watch.port))
                } else if !wasActive, isActive, watch.notifyOnStart {
                    events.append(.started(port: watch.port, processName: active[watch.port] ?? ""))
                }
            }
            previous[watch.port] = isActive
        }
        return events
    }
}

public struct ArrivalMonitor: Sendable {
    private var known: Set<String>?

    public init() {}

    public mutating func arrivals(in ports: [ListeningPort]) -> [ListeningPort] {
        let ids = Set(ports.map(\.id))
        defer { known = ids }
        guard let known else { return [] }
        return ports.filter { !known.contains($0.id) }
    }
}
