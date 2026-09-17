import Foundation

public struct PortFilter: Sendable, Equatable {
    public var searchText = ""
    public var minPort: Int?
    public var maxPort: Int?
    public var categories: Set<ProcessCategory> = Set(ProcessCategory.allCases)

    public init(searchText: String = "", minPort: Int? = nil, maxPort: Int? = nil, categories: Set<ProcessCategory> = Set(ProcessCategory.allCases)) {
        self.searchText = searchText
        self.minPort = minPort
        self.maxPort = maxPort
        self.categories = categories
    }

    public var isActive: Bool {
        !query.isEmpty || minPort != nil || maxPort != nil || categories.count < ProcessCategory.allCases.count
    }

    public var hasRange: Bool {
        minPort != nil || maxPort != nil
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public func matches(_ port: ListeningPort, category: ProcessCategory, label: String? = nil) -> Bool {
        if let minPort, port.port < minPort { return false }
        if let maxPort, port.port > maxPort { return false }
        guard categories.contains(category) else { return false }
        let query = query
        guard !query.isEmpty else { return true }
        let fields = [
            String(port.port),
            String(port.pid),
            port.processName,
            port.address,
            port.process.user,
            port.process.command,
            label ?? "",
        ]
        return fields.contains { $0.lowercased().contains(query) }
    }

    public mutating func reset() {
        self = PortFilter()
    }
}
