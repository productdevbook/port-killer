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

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct PluginInput: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case text
        case multiline
        case secret
        case number
        case toggle
        case choice
    }

    public var id: String
    public var label: String
    public var type: Kind?
    public var placeholder: String?
    public var defaultValue: String?
    public var options: [String]?
    public var required: Bool?
    public var help: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case type
        case placeholder
        case defaultValue = "default"
        case options
        case required
        case help
    }

    public init(
        id: String,
        label: String,
        type: Kind? = nil,
        placeholder: String? = nil,
        defaultValue: String? = nil,
        options: [String]? = nil,
        required: Bool? = nil,
        help: String? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.placeholder = placeholder
        self.defaultValue = defaultValue
        self.options = options
        self.required = required
        self.help = help
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decodeIfPresent(Kind.self, forKey: .type)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        options = try container.decodeIfPresent([String].self, forKey: .options)
        required = try container.decodeIfPresent(Bool.self, forKey: .required)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        if let text = try? container.decodeIfPresent(String.self, forKey: .defaultValue) {
            defaultValue = text
        } else if let flag = try? container.decodeIfPresent(Bool.self, forKey: .defaultValue) {
            defaultValue = String(flag)
        } else if let number = try? container.decodeIfPresent(Int.self, forKey: .defaultValue) {
            defaultValue = String(number)
        } else if let number = try? container.decodeIfPresent(Double.self, forKey: .defaultValue) {
            defaultValue = String(number)
        } else {
            defaultValue = nil
        }
    }

    public var kind: Kind { type ?? .text }

    public var isRequired: Bool { required ?? false }

    public var initialValue: String {
        if let defaultValue { return defaultValue }
        return switch kind {
        case .toggle: "false"
        case .choice: options?.first ?? ""
        case .text, .multiline, .secret, .number: ""
        }
    }

    public var environmentName: String {
        "PORTKILLER_SETTING_" + String(id.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }

    public func problem(with value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return isRequired && kind != .toggle ? "\(label) is required." : nil
        }
        return switch kind {
        case .number: Double(trimmed) == nil ? "\(label) must be a number." : nil
        case .toggle: trimmed == "true" || trimmed == "false" ? nil : "\(label) must be true or false."
        case .choice: options?.contains(value) == true ? nil : "\(label) must be one of \((options ?? []).joined(separator: ", "))."
        case .text, .multiline, .secret: nil
        }
    }
}

extension [PluginInput] {
    public func values(remembered: [String: String] = [:]) -> [String: String] {
        Dictionary(map { input in
            let value = remembered[input.id].flatMap { input.problem(with: $0) == nil ? $0 : nil }
            return (input.id, value ?? input.initialValue)
        }) { first, _ in first }
    }

    public func problems(in values: [String: String]) -> [String] {
        compactMap { $0.problem(with: values[$0.id] ?? $0.initialValue) }
    }

    func definitionProblem(in owner: String) -> String? {
        var seen: Set<String> = []
        for input in self {
            guard input.id.wholeMatch(of: /[A-Za-z0-9_-]+/) != nil else {
                return "\(owner) has an input whose id isn't made of letters, digits, dashes and underscores."
            }
            guard seen.insert(input.id).inserted else { return "\(owner) has more than one input with the id \(input.id)." }
            if input.kind == .choice, input.options?.isEmpty ?? true {
                return "\(owner) input \(input.id) is a choice without options."
            }
            if let defaultValue = input.defaultValue, input.problem(with: defaultValue) != nil {
                return "\(owner) input \(input.id) has a default that doesn't fit its type."
            }
        }
        return nil
    }
}

public struct PluginAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String?
    public var destructive: Bool?
    public var confirmation: String?
    public var inputs: [PluginInput]?

    public init(id: String, title: String, icon: String? = nil, destructive: Bool? = nil, confirmation: String? = nil, inputs: [PluginInput]? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.confirmation = confirmation
        self.inputs = inputs
    }
}

public struct PluginItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var status: PluginItemStatus?
    public var port: Int?
    public var targetPorts: [Int]?
    public var url: URL?
    public var fields: [PluginField]?
    public var actions: [PluginAction]?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        status: PluginItemStatus? = nil,
        port: Int? = nil,
        targetPorts: [Int]? = nil,
        url: URL? = nil,
        fields: [PluginField]? = nil,
        actions: [PluginAction]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.port = port
        self.targetPorts = targetPorts
        self.url = url
        self.fields = fields
        self.actions = actions
    }
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

public struct PluginDetails: Codable, Sendable, Hashable {
    public var title: String?
    public var fields: [PluginField]?
    public var text: String?

    public init(title: String? = nil, fields: [PluginField]? = nil, text: String? = nil) {
        self.title = title
        self.fields = fields
        self.text = text
    }
}

public struct PluginActionResult: Codable, Sendable, Hashable {
    public var message: String?
    public var open: URL?
    public var copy: String?
    public var refresh: Bool?
    public var details: PluginDetails?
    public var log: String?

    enum CodingKeys: String, CodingKey {
        case message
        case open
        case copy
        case refresh
        case details
    }

    public init(message: String? = nil, open: URL? = nil, copy: String? = nil, refresh: Bool? = nil, details: PluginDetails? = nil, log: String? = nil) {
        self.message = message
        self.open = open
        self.copy = copy
        self.refresh = refresh
        self.details = details
        self.log = log
    }
}

struct PluginItemsResponse: Codable, Sendable {
    var items: [PluginItem]
}

struct PluginItemActionRequest: Codable, Sendable {
    var action: String
    var item: String
    var inputs: [String: String]?
}

struct PluginPortActionRequest: Codable, Sendable {
    var action: String
    var port: PluginPortContext
    var inputs: [String: String]?
}

struct PluginEmptyRequest: Codable, Sendable {}
