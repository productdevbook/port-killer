import Foundation

struct PortFilter: Equatable, Sendable {
    var searchText: String = ""
    var minPort: Int? = nil
    var maxPort: Int? = nil
    var processTypes: Set<ProcessType> = Set(ProcessType.allCases)
    var showOnlyFavorites: Bool = false
    var showOnlyWatched: Bool = false

    var isActive: Bool {
        !searchText.isEmpty ||
        minPort != nil ||
        maxPort != nil ||
        processTypes.count < ProcessType.allCases.count ||
        showOnlyFavorites ||
        showOnlyWatched
    }

    func matches(_ port: PortInfo, favorites: Set<Int>, watched: [WatchedPort]) -> Bool {
        // Search text filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            let matches = port.processName.lowercased().contains(query) ||
                          String(port.port).contains(query) ||
                          String(port.pid).contains(query) ||
                          port.address.lowercased().contains(query) ||
                          port.user.lowercased().contains(query) ||
                          port.command.lowercased().contains(query)
            if !matches { return false }
        }

        // Port range filter
        if let min = minPort, port.port < min { return false }
        if let max = maxPort, port.port > max { return false }

        // Process type filter
        if !processTypes.contains(port.processType) { return false }

        // Favorites filter
        if showOnlyFavorites && !favorites.contains(port.port) { return false }

        // Watched filter
        if showOnlyWatched && !watched.contains(where: { $0.port == port.port }) { return false }

        return true
    }

    mutating func reset() {
        searchText = ""
        minPort = nil
        maxPort = nil
        processTypes = Set(ProcessType.allCases)
        showOnlyFavorites = false
        showOnlyWatched = false
    }
}

enum SidebarItem: Hashable, Identifiable {
    case allPorts
    case favorites
    case watched
    case processType(ProcessType)
    case sponsors
    case settings

    var id: String {
        switch self {
        case .allPorts: return "all"
        case .favorites: return "favorites"
        case .watched: return "watched"
        case .processType(let type): return "type-\(type.rawValue)"
        case .sponsors: return "sponsors"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .allPorts: return "All Ports"
        case .favorites: return "Favorites"
        case .watched: return "Watched"
        case .processType(let type): return type.rawValue
        case .sponsors: return "Sponsors"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .allPorts: return "list.bullet"
        case .favorites: return "star.fill"
        case .watched: return "eye.fill"
        case .processType(let type): return type.icon
        case .sponsors: return "heart.fill"
        case .settings: return "gear"
        }
    }
}
