public import Foundation

public struct AutoKillRule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var processPattern: String
    public var port: Int
    public var timeoutMinutes: Int
    public var notifyBeforeKill: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        processPattern: String = "",
        port: Int = 0,
        timeoutMinutes: Int = 30,
        notifyBeforeKill: Bool = true,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.processPattern = processPattern
        self.port = port
        self.timeoutMinutes = timeoutMinutes
        self.notifyBeforeKill = notifyBeforeKill
        self.isEnabled = isEnabled
    }

    public var isValid: Bool {
        !processPattern.trimmingCharacters(in: .whitespaces).isEmpty || port > 0
    }

    public func matches(port candidate: Int, processName: String) -> Bool {
        if port > 0 && candidate != port { return false }
        let pattern = processPattern.trimmingCharacters(in: .whitespaces)
        if !pattern.isEmpty {
            return Self.glob(pattern.lowercased(), matches: processName.lowercased())
        }
        return port > 0
    }

    static func glob(_ pattern: String, matches text: String) -> Bool {
        guard pattern.contains("*") else { return pattern == text }
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        if let first = parts.first, !first.isEmpty, !text.hasPrefix(first) { return false }
        if let last = parts.last, !last.isEmpty, !text.hasSuffix(last) { return false }
        var searchStart = text.startIndex
        for part in parts where !part.isEmpty {
            guard let range = text.range(of: part, range: searchStart..<text.endIndex) else { return false }
            searchStart = range.upperBound
        }
        return true
    }
}

public struct AutoKillMonitor: Sendable {
    public struct Match: Sendable, Hashable {
        public var port: ListeningPort
        public var rule: AutoKillRule
    }

    private var firstSeen: [String: Date] = [:]

    public init() {}

    public mutating func due(ports: [ListeningPort], rules: [AutoKillRule], now: Date = Date()) -> [Match] {
        let enabled = rules.filter { $0.isEnabled && $0.isValid }
        guard !enabled.isEmpty else {
            firstSeen = [:]
            return []
        }
        let current = Set(ports.map(\.id))
        firstSeen = firstSeen.filter { current.contains($0.key) }
        var matches: [Match] = []
        for port in ports {
            let seen = firstSeen[port.id] ?? now
            firstSeen[port.id] = seen
            guard let rule = enabled.first(where: { $0.matches(port: port.port, processName: port.processName) }) else { continue }
            guard now.timeIntervalSince(seen) >= Double(rule.timeoutMinutes) * 60 else { continue }
            matches.append(Match(port: port, rule: rule))
            firstSeen[port.id] = nil
        }
        return matches
    }
}
