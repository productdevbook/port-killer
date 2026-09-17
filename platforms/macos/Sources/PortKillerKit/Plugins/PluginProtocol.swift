public import Foundation

public enum PluginItemStatus: String, Codable, Sendable, Hashable {
    case running
    case stopped
    case warning
    case error
}

public struct PluginField: Codable, Sendable, Hashable {
    public var label: String
    public var value: String
}

public struct PluginAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    public var destructive: Bool?
}

public struct PluginItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var status: PluginItemStatus?
    public var port: Int?
    public var url: URL?
    public var fields: [PluginField]?
    public var actions: [PluginAction]?
}

public struct PluginPortContext: Codable, Sendable, Hashable {
    public var port: Int
    public var pid: Int32
    public var process: String
    public var command: String
    public var executable: String?
    public var user: String
    public var addresses: [String]

    public init(_ listener: ListeningPort) {
        port = listener.port
        pid = listener.pid
        process = listener.processName
        command = listener.process.command
        executable = listener.process.executablePath
        user = listener.process.user
        addresses = listener.addresses
    }
}

public struct PluginActionResult: Codable, Sendable, Hashable {
    public var message: String?
    public var open: URL?
    public var copy: String?
    public var refresh: Bool?

    public init(message: String? = nil, open: URL? = nil, copy: String? = nil, refresh: Bool? = nil) {
        self.message = message
        self.open = open
        self.copy = copy
        self.refresh = refresh
    }
}

struct PluginItemsResponse: Codable, Sendable {
    var items: [PluginItem]
}

struct PluginItemActionRequest: Codable, Sendable {
    var action: String
    var item: String
}

struct PluginPortActionRequest: Codable, Sendable {
    var action: String
    var port: PluginPortContext
}

struct PluginEmptyRequest: Codable, Sendable {}
