import AppKit
import Observation
import OrderedCollections
import PortKillerKit

enum SidebarItem: Hashable {
    case allPorts
    case favorites
    case watched
    case category(ProcessCategory)
    case portForwards
    case tunnels
    case sponsors

    init?(storageValue: String) {
        switch storageValue {
        case "all": self = .allPorts
        case "favorites": self = .favorites
        case "watched": self = .watched
        case "forwards": self = .portForwards
        case "tunnels": self = .tunnels
        case "sponsors": self = .sponsors
        default:
            guard let category = ProcessCategory(rawValue: storageValue) else { return nil }
            self = .category(category)
        }
    }

    var storageValue: String {
        switch self {
        case .allPorts: "all"
        case .favorites: "favorites"
        case .watched: "watched"
        case .category(let category): category.rawValue
        case .portForwards: "forwards"
        case .tunnels: "tunnels"
        case .sponsors: "sponsors"
        }
    }
}

enum KillMode: Hashable {
    case graceful
    case force
    case deep
    case tree
}

struct PresentedError: LocalizedError {
    var title: String
    var message: String

    var errorDescription: String? { title }
    var recoverySuggestion: String? { message }
}

nonisolated struct PortRow: Identifiable, Hashable {
    enum ID: Hashable {
        case listener(ListeningPort.ID)
        case group(String)
        case inactive(Int)

        var inactivePort: Int? {
            if case .inactive(let port) = self { port } else { nil }
        }
    }

    var id: ID
    var port: Int
    var listener: ListeningPort?
    var category: ProcessCategory
    var label: String?
    var isFavorite: Bool
    var isWatched: Bool
    var address = ""
    var children: [PortRow]?

    var processName: String { listener?.processName ?? "Not Running" }
    var pid: Int { Int(listener?.pid ?? 0) }
    var user: String { listener?.process.user ?? "" }
    var startDate: Date { listener?.process.startDate ?? .distantFuture }
    var categoryName: String { listener == nil ? "" : category.rawValue }
}

@Observable
final class PortStore {
    let preferences: Preferences
    let notifier: Notifier

    private(set) var ports: [ListeningPort] = []
    private(set) var isScanning = false
    private(set) var terminating: Set<String> = []
    var filter = PortFilter()
    var selection: Set<PortRow.ID> = []
    var sortOrder = [KeyPathComparator(\PortRow.port)]
    var pendingKill: [ListeningPort] = []
    var error: PresentedError?

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var watchMonitor = WatchMonitor()
    @ObservationIgnored private var autoKillMonitor = AutoKillMonitor()
    @ObservationIgnored private var arrivalMonitor = ArrivalMonitor()
    @ObservationIgnored private var detectedCategories: [String: ProcessCategory] = [:]

    init(preferences: Preferences, notifier: Notifier) {
        self.preferences = preferences
        self.notifier = notifier
    }

    func start() {
        guard loop == nil else { return }
        notifier.onKill = { [weak self] request in
            guard let self, let port = ports.first(where: { $0.port == request.port && $0.pid == request.pid }) else { return }
            Task(name: "Kill from notification") { await self.kill(port) }
        }
        loop = Task(name: "Port scan loop") { [weak self] in
            var unchangedScans = 0
            while !Task.isCancelled {
                let changed = await self?.refresh() ?? false
                unchangedScans = changed ? 0 : min(unchangedScans + 1, 60)
                let base = Double(max(1, self?.preferences.refreshInterval ?? 3))
                let backoff = unchangedScans < 20 ? 1.0 : unchangedScans < 40 ? 1.5 : 2.0
                try? await Task.sleep(for: .seconds(min(base * backoff, 30)))
            }
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        guard !isScanning else {
            pendingRefresh = true
            return false
        }
        isScanning = true
        defer { isScanning = false }
        var changed = false
        repeat {
            pendingRefresh = false
            let scanned = await PortScanner.scan()
            if scanned != ports {
                ports = scanned
                changed = true
            }
            evaluateRules(scanned)
        } while pendingRefresh
        return changed
    }

    func category(for port: ListeningPort) -> ProcessCategory {
        if let override = preferences.categoryOverride(for: port.processName) { return override }
        if let detected = detectedCategories[port.processName] { return detected }
        let detected = ProcessCategory.detect(port.processName)
        detectedCategories[port.processName] = detected
        return detected
    }

    func rows(for item: SidebarItem, filter: PortFilter? = nil) -> [PortRow] {
        let filter = filter ?? self.filter
        let hideSystem = preferences.hideSystemProcesses && item != .category(.system)
        let listening = ports.map(row(for:))
        var rows = listening.filter { !(hideSystem && $0.category == .system) }
        switch item {
        case .favorites:
            rows = rows.filter(\.isFavorite) + inactiveRows(for: preferences.favorites, active: listening)
        case .watched:
            rows = rows.filter(\.isWatched) + inactiveRows(for: Set(preferences.watchedPorts.map(\.port)), active: listening)
        case .category(let category):
            rows = rows.filter { $0.category == category }
        default:
            break
        }
        return rows.filter { row in
            guard let listener = row.listener else {
                return filter.searchText.isEmpty || String(row.port).contains(filter.searchText)
            }
            return filter.matches(listener, category: row.category, label: row.label)
        }
    }

    var categoryCounts: [ProcessCategory: Int] {
        ports.reduce(into: [:]) { counts, port in counts[category(for: port), default: 0] += 1 }
    }

    static func grouped(_ rows: [PortRow]) -> [PortRow] {
        let groups = OrderedDictionary(grouping: rows.filter { $0.listener != nil }, by: \.processName)
        return groups.map { name, members in
            guard members.count > 1, let first = members.first else { return members[0] }
            return PortRow(
                id: .group(name),
                port: first.port,
                listener: first.listener,
                category: first.category,
                label: nil,
                isFavorite: members.contains(where: \.isFavorite),
                isWatched: members.contains(where: \.isWatched),
                address: first.address,
                children: members
            )
        } + rows.filter { $0.listener == nil }
    }

    func row(for listener: ListeningPort) -> PortRow {
        PortRow(
            id: .listener(listener.id),
            port: listener.port,
            listener: listener,
            category: category(for: listener),
            label: preferences.label(for: listener.port),
            isFavorite: preferences.favorites.contains(listener.port),
            isWatched: preferences.isWatching(listener.port),
            address: listener.address
        )
    }

    private func inactiveRows(for ports: Set<Int>, active: [PortRow]) -> [PortRow] {
        let activePorts = Set(active.map(\.port))
        return ports.subtracting(activePorts).sorted().map { port in
            PortRow(
                id: .inactive(port),
                port: port,
                listener: nil,
                category: .other,
                label: preferences.label(for: port),
                isFavorite: preferences.favorites.contains(port),
                isWatched: preferences.isWatching(port)
            )
        }
    }

    func parent(of port: ListeningPort) async -> ProcessSnapshot? {
        await PortScanner.parent(of: port.process)
    }

    func listeners(ids: Set<PortRow.ID>, in item: SidebarItem) -> [ListeningPort] {
        var groups: Set<String> = []
        var result: [ListeningPort] = []
        for id in ids {
            switch id {
            case .listener(let listenerID):
                if let port = ports.first(where: { $0.id == listenerID }) { result.append(port) }
            case .group(let name):
                groups.insert(name)
            case .inactive:
                break
            }
        }
        if !groups.isEmpty {
            result += rows(for: item).filter { groups.contains($0.processName) }.compactMap(\.listener)
        }
        return Array(Set(result)).sorted { $0.port < $1.port }
    }

    func requestKill(_ targets: [ListeningPort]) {
        guard !targets.isEmpty else { return }
        if preferences.skipKillConfirmation {
            Task { await kill(targets) }
        } else {
            pendingKill = targets
        }
    }

    func kill(_ port: ListeningPort, mode: KillMode = .graceful) async {
        await terminate(port, mode: mode)
        await refresh()
    }

    func kill(_ ports: [ListeningPort], mode: KillMode = .graceful) async {
        await withDiscardingTaskGroup { group in
            for port in Set(ports) {
                group.addTask(name: "Kill \(port.id)") { await self.terminate(port, mode: mode) }
            }
        }
        await refresh()
    }

    private func terminate(_ port: ListeningPort, mode: KillMode) async {
        terminating.insert(port.id)
        defer { terminating.remove(port.id) }
        do {
            switch mode {
            case .graceful:
                try await ProcessTerminator.terminate(port.pid)
            case .force:
                try await ProcessTerminator.terminate(port.pid, force: true)
            case .tree:
                try await ProcessTerminator.terminateTree(port.pid)
            case .deep:
                try await ProcessTerminator.terminate(port.pid)
                let ownPID = ProcessInfo.processInfo.processIdentifier
                for pid in await PortScanner.establishedPIDs(port: port.port) where pid != port.pid && pid != ownPID {
                    try? await ProcessTerminator.terminate(pid)
                }
            }
        } catch {
            self.error = PresentedError(title: "Couldn't Kill \(port.processName)", message: error.localizedDescription)
        }
    }

    func removeInactive(_ port: Int) {
        preferences.favorites.remove(port)
        preferences.watchedPorts.removeAll { $0.port == port }
    }

    private func evaluateRules(_ scanned: [ListeningPort]) {
        for event in watchMonitor.events(watched: preferences.watchedPorts, ports: scanned) {
            switch event {
            case .started(let port, let processName):
                let listener = scanned.first { $0.port == port }
                notifier.post(
                    title: "Port \(port) In Use",
                    body: "Used by \(processName).",
                    killing: listener.map { Notifier.KillRequest(port: port, pid: $0.pid) }
                )
            case .stopped(let port):
                notifier.post(title: "Port \(port) Available", body: "Port \(port) is free again.")
            }
        }

        let arrivals = arrivalMonitor.arrivals(in: scanned)
        let categories = preferences.notifyCategories
        for port in arrivals where categories.contains(category(for: port).rawValue) {
            notifier.post(
                title: "New \(category(for: port).rawValue) on Port \(port.port)",
                body: "\(port.processName) started listening.",
                killing: Notifier.KillRequest(port: port.port, pid: port.pid)
            )
        }

        for match in autoKillMonitor.due(ports: scanned, rules: preferences.autoKillRules) {
            if match.rule.notifyBeforeKill {
                notifier.post(
                    title: "Auto-Kill: \(match.port.processName)",
                    body: "Port \(match.port.port) stopped after \(match.rule.timeoutMinutes) min (rule: \(match.rule.name.isEmpty ? "Unnamed" : match.rule.name))."
                )
            }
            Task(name: "Auto-kill \(match.port.id)") { [weak self] in
                await self?.kill(match.port)
            }
        }
    }
}
