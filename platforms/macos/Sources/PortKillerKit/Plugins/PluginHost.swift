public import Foundation

public struct Plugin: Sendable, Hashable, Identifiable {
    public var manifest: PluginManifest
    public var bundleURL: URL
    public var dataURL: URL

    public var id: String { manifest.id }

    public var executableURL: URL {
        bundleURL.appending(path: manifest.executable)
    }
}

public struct PluginLoadFailure: Sendable, Hashable, Identifiable {
    public var bundleURL: URL
    public var message: String

    public var id: URL { bundleURL }
}

public enum PluginError: Error, LocalizedError, Sendable, Equatable {
    case invalidManifest(String)
    case unsupportedAPIVersion(Int)
    case invalidExecutable(String)
    case launchFailed(String)
    case failed(status: Int32, message: String)
    case timedOut
    case unreadableResponse(String)
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let message): "plugin.json is invalid: \(message)"
        case .unsupportedAPIVersion(let version): "The plugin needs API version \(version). This PortKiller supports version \(PluginHost.apiVersion)."
        case .invalidExecutable(let message): message
        case .launchFailed(let message): "The plugin couldn't start: \(message)"
        case .failed(let status, let message): message.isEmpty ? "The plugin exited with status \(status)." : message
        case .timedOut: "The plugin didn't answer in time."
        case .unreadableResponse(let message): "The plugin's answer isn't valid: \(message)"
        case .installFailed(let message): message
        }
    }
}

public enum PluginHost {
    public static let apiVersion = 1
    public static let bundleExtension = "portkillerplugin"
    static let manifestName = "plugin.json"
    static let timeout = Duration.seconds(15)

    public static var directory: URL {
        supportDirectory.appending(path: "Plugins", directoryHint: .isDirectory)
    }

    public static var dataRoot: URL {
        supportDirectory.appending(path: "PluginData", directoryHint: .isDirectory)
    }

    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appending(path: "PortKiller", directoryHint: .isDirectory)
    }

    public static func discover(in directory: URL = directory, dataRoot: URL = dataRoot) -> (plugins: [Plugin], failures: [PluginLoadFailure]) {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        var plugins: [Plugin] = []
        var failures: [PluginLoadFailure] = []
        for bundle in contents.filter({ $0.pathExtension == bundleExtension }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let plugin = try load(bundle, dataRoot: dataRoot)
                if plugins.contains(where: { $0.id == plugin.id }) {
                    failures.append(PluginLoadFailure(bundleURL: bundle, message: "Another plugin already uses the ID \(plugin.id)."))
                } else {
                    plugins.append(plugin)
                }
            } catch {
                failures.append(PluginLoadFailure(bundleURL: bundle, message: error.localizedDescription))
            }
        }
        return (plugins, failures)
    }

    public static func load(_ bundleURL: URL, dataRoot: URL = dataRoot) throws(PluginError) -> Plugin {
        let manifest: PluginManifest
        do {
            let data = try Data(contentsOf: bundleURL.appending(path: manifestName))
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            throw .invalidManifest(describe(error))
        }
        guard manifest.apiVersion == apiVersion else { throw .unsupportedAPIVersion(manifest.apiVersion) }
        if let problem = manifest.problem { throw .invalidManifest(problem) }
        let plugin = Plugin(manifest: manifest, bundleURL: bundleURL, dataURL: dataRoot.appending(path: manifest.id, directoryHint: .isDirectory))
        let bundlePath = bundleURL.standardizedFileURL.path
        let executablePath = plugin.executableURL.standardizedFileURL.path
        guard !manifest.executable.hasPrefix("/"), executablePath.hasPrefix(bundlePath + "/") else {
            throw .invalidExecutable("The executable must be inside the plugin folder.")
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw .invalidExecutable("\(manifest.executable) is missing or isn't executable. Run chmod +x on it.")
        }
        return plugin
    }

    public static func install(_ source: URL, into directory: URL = directory, dataRoot: URL = dataRoot) throws(PluginError) -> Plugin {
        guard source.pathExtension == bundleExtension else {
            throw .installFailed("Choose a folder whose name ends in .\(bundleExtension).")
        }
        let plugin = try load(source, dataRoot: dataRoot)
        let destination = directory.appending(path: source.lastPathComponent, directoryHint: .isDirectory)
        guard source.standardizedFileURL.path != destination.standardizedFileURL.path else { return plugin }
        let manager = FileManager.default
        let staging = directory.appending(path: ".\(UUID().uuidString).\(bundleExtension)", directoryHint: .isDirectory)
        let replaced = discover(in: directory, dataRoot: dataRoot).plugins.filter { $0.id == plugin.id }.map(\.bundleURL)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: staging)
            for bundle in Set(replaced + [destination]) where manager.fileExists(atPath: bundle.path) {
                try manager.removeItem(at: bundle)
            }
            try manager.moveItem(at: staging, to: destination)
        } catch {
            try? manager.removeItem(at: staging)
            throw .installFailed("PortKiller couldn't copy the plugin: \(error.localizedDescription)")
        }
        return try load(destination, dataRoot: dataRoot)
    }

    @concurrent
    public static func items(of plugin: Plugin, settings: [String: String] = [:]) async throws(PluginError) -> [PluginItem] {
        let items = try await call(plugin, command: "items", request: PluginEmptyRequest(), as: PluginItemsResponse.self, settings: settings).items
        var ids: Set<String> = []
        for item in items {
            guard ids.insert(item.id).inserted else { throw .unreadableResponse("More than one item has the id \(item.id).") }
            for action in item.actions ?? [] {
                if let problem = (action.inputs ?? []).definitionProblem(in: "Action \(action.id) of item \(item.id)") {
                    throw .unreadableResponse(problem)
                }
            }
        }
        return items
    }

    @concurrent
    public static func perform(
        _ action: String,
        onItem item: String,
        inputs: [String: String] = [:],
        settings: [String: String] = [:],
        in plugin: Plugin
    ) async throws(PluginError) -> PluginActionResult {
        let request = PluginItemActionRequest(action: action, item: item, inputs: inputs.isEmpty ? nil : inputs)
        return try await act(plugin, command: "perform", request: request, settings: settings)
    }

    @concurrent
    public static func perform(
        _ action: String,
        onPort port: PluginPortContext,
        inputs: [String: String] = [:],
        connection: UUID? = nil,
        settings: [String: String] = [:],
        in plugin: Plugin
    ) async throws(PluginError) -> PluginActionResult {
        let request = PluginPortActionRequest(action: action, port: port, inputs: inputs.isEmpty ? nil : inputs, connection: connection)
        return try await act(plugin, command: "port-action", request: request, settings: settings)
    }

    public static func environment(for plugin: Plugin, settings: [String: String]) -> [String: String] {
        var environment = [
            "PORTKILLER_API_VERSION": String(apiVersion),
            "PORTKILLER_PLUGIN_ID": plugin.id,
            "PORTKILLER_PLUGIN_DIR": plugin.bundleURL.path,
            "PORTKILLER_DATA_DIR": plugin.dataURL.path,
        ]
        for input in plugin.manifest.settings ?? [] {
            environment[input.environmentName] = settings[input.id] ?? input.initialValue
        }
        return environment
    }

    static func call<Request: Encodable & Sendable, Response: Decodable>(
        _ plugin: Plugin,
        command: String,
        request: Request,
        as type: Response.Type,
        settings: [String: String] = [:],
        timeout: Duration = timeout
    ) async throws(PluginError) -> Response {
        try await run(plugin, command: command, request: request, as: type, settings: settings, timeout: timeout).response
    }

    private static func act<Request: Encodable & Sendable>(_ plugin: Plugin, command: String, request: Request, settings: [String: String]) async throws(PluginError) -> PluginActionResult {
        var (result, log) = try await run(plugin, command: command, request: request, as: PluginActionResult.self, settings: settings, timeout: timeout)
        result.log = log.isEmpty ? nil : log
        return result
    }

    private static func run<Request: Encodable & Sendable, Response: Decodable>(
        _ plugin: Plugin,
        command: String,
        request: Request,
        as type: Response.Type,
        settings: [String: String],
        timeout: Duration
    ) async throws(PluginError) -> (response: Response, log: String) {
        let input: String
        do {
            input = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        let result: CommandResult
        do {
            try FileManager.default.createDirectory(at: plugin.dataURL, withIntermediateDirectories: true)
            result = try await CommandRunner.run(
                plugin.executableURL,
                [command],
                input: input,
                environment: environment(for: plugin, settings: settings),
                timeout: timeout
            )
        } catch is CommandTimedOut {
            throw .timedOut
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        guard result.succeeded else {
            throw .failed(status: result.status, message: String(result.error.trimmingCharacters(in: .whitespacesAndNewlines).suffix(500)))
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let response = try JSONDecoder().decode(Response.self, from: Data((output.isEmpty ? "{}" : output).utf8))
            return (response, String(result.error.trimmingCharacters(in: .whitespacesAndNewlines).suffix(4000)))
        } catch {
            throw .unreadableResponse(describe(error))
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let context):
            "\(path(context.codingPath + [key])) is missing."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "\(path(context.codingPath)) has the wrong type."
        case DecodingError.dataCorrupted(let context):
            context.codingPath.isEmpty ? "It isn't valid JSON." : "\(path(context.codingPath)) is invalid."
        default:
            error.localizedDescription
        }
    }

    private static func path(_ codingPath: [any CodingKey]) -> String {
        String(codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined().trimmingPrefix("."))
    }
}
