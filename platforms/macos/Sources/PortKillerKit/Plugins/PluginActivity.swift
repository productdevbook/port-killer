public import Foundation

public struct PluginRun: Identifiable, Sendable, Hashable {
    public enum Target: Sendable, Hashable {
        case port(Int)
        case item(String)
    }

    public enum State: Sendable, Hashable {
        case running
        case succeeded(PluginActionResult)
        case failed(String)
    }

    public let id: UUID
    public var pluginID: String
    public var actionID: String
    public var connectionID: PluginConnection.ID?
    public var title: String
    public var target: Target
    public var started: Date
    public var finished: Date?
    public var state: State

    public init(id: UUID = UUID(), pluginID: String, actionID: String, connectionID: PluginConnection.ID? = nil, title: String, target: Target, started: Date = .now) {
        self.id = id
        self.pluginID = pluginID
        self.actionID = actionID
        self.connectionID = connectionID
        self.title = title
        self.target = target
        self.started = started
        state = .running
    }

    public var isRunning: Bool {
        state == .running
    }

    public var result: PluginActionResult? {
        if case .succeeded(let result) = state { result } else { nil }
    }

    public var duration: Duration? {
        finished.map { .milliseconds(Int(($0.timeIntervalSince(started) * 1000).rounded())) }
    }

    public var summary: String {
        switch state {
        case .running: "Running…"
        case .succeeded(let result): result.message ?? result.details?.title ?? "Done"
        case .failed(let message): message
        }
    }
}

public struct PluginActivity: Sendable, Hashable {
    public private(set) var runs: [PluginRun] = []
    public var limit: Int

    public init(limit: Int = 200) {
        self.limit = limit
    }

    @discardableResult
    public mutating func start(_ run: PluginRun) -> PluginRun.ID {
        runs.insert(run, at: 0)
        if runs.count > limit {
            runs.removeLast(runs.count - limit)
        }
        return run.id
    }

    public mutating func finish(_ id: PluginRun.ID, as state: PluginRun.State, at date: Date = .now) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].state = state
        runs[index].finished = date
    }

    public func run(_ id: PluginRun.ID) -> PluginRun? {
        runs.first { $0.id == id }
    }

    public func latest(plugin: String, action: String) -> PluginRun? {
        runs.first { $0.pluginID == plugin && $0.actionID == action }
    }

    public func latest(connection: PluginConnection.ID) -> PluginRun? {
        runs.first { $0.connectionID == connection }
    }

    public func isRunning(plugin: String, action: String, target: PluginRun.Target) -> Bool {
        runs.contains { $0.pluginID == plugin && $0.actionID == action && $0.target == target && $0.isRunning }
    }

    public func runs(for target: PluginRun.Target, plugin: String? = nil) -> [PluginRun] {
        runs.filter { $0.target == target && (plugin == nil || $0.pluginID == plugin) }
    }

    public mutating func removeRuns(of plugin: String) {
        runs.removeAll { $0.pluginID == plugin && !$0.isRunning }
    }
}
