public import Foundation

public struct Plugin: Sendable, Hashable, Identifiable {
    public var manifest: PluginManifest
    public var bundleURL: URL

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

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let message): "plugin.json is invalid: \(message)"
        case .unsupportedAPIVersion(let version): "The plugin needs API version \(version). This PortKiller supports version \(PluginHost.apiVersion)."
        case .invalidExecutable(let message): message
        case .launchFailed(let message): "The plugin couldn't start: \(message)"
        case .failed(let status, let message): message.isEmpty ? "The plugin exited with status \(status)." : message
        case .timedOut: "The plugin didn't answer in time."
        case .unreadableResponse(let message): "The plugin's answer isn't valid: \(message)"
        }
    }
}

public enum PluginHost {
    public static let apiVersion = 1
    public static let bundleExtension = "portkillerplugin"
    static let manifestName = "plugin.json"
    static let timeout = Duration.seconds(15)

    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "PortKiller/Plugins", directoryHint: .isDirectory)
    }

    public static func discover(in directory: URL = directory) -> (plugins: [Plugin], failures: [PluginLoadFailure]) {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var plugins: [Plugin] = []
        var failures: [PluginLoadFailure] = []
        for bundle in contents.filter({ $0.pathExtension == bundleExtension }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let plugin = try load(bundle)
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

    public static func load(_ bundleURL: URL) throws(PluginError) -> Plugin {
        let manifest: PluginManifest
        do {
            let data = try Data(contentsOf: bundleURL.appending(path: manifestName))
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            throw .invalidManifest(describe(error))
        }
        guard manifest.apiVersion == apiVersion else { throw .unsupportedAPIVersion(manifest.apiVersion) }
        guard manifest.id.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9._-]*/) != nil else {
            throw .invalidManifest("id may only contain letters, digits, dots, dashes and underscores.")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw .invalidManifest("name is empty.") }
        let plugin = Plugin(manifest: manifest, bundleURL: bundleURL)
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

    @concurrent
    public static func items(of plugin: Plugin) async throws(PluginError) -> [PluginItem] {
        try await call(plugin, command: "items", request: PluginEmptyRequest(), as: PluginItemsResponse.self).items
    }

    @concurrent
    public static func perform(_ action: String, onItem item: String, in plugin: Plugin) async throws(PluginError) -> PluginActionResult {
        try await call(plugin, command: "perform", request: PluginItemActionRequest(action: action, item: item), as: PluginActionResult.self)
    }

    @concurrent
    public static func perform(_ action: String, onPort port: PluginPortContext, in plugin: Plugin) async throws(PluginError) -> PluginActionResult {
        try await call(plugin, command: "port-action", request: PluginPortActionRequest(action: action, port: port), as: PluginActionResult.self)
    }

    static func call<Request: Encodable & Sendable, Response: Decodable>(
        _ plugin: Plugin,
        command: String,
        request: Request,
        as type: Response.Type,
        timeout: Duration = timeout
    ) async throws(PluginError) -> Response {
        let input: String
        do {
            input = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        let result: CommandResult
        do {
            result = try await CommandRunner.run(
                plugin.executableURL,
                [command],
                input: input,
                environment: [
                    "PORTKILLER_API_VERSION": String(apiVersion),
                    "PORTKILLER_PLUGIN_ID": plugin.id,
                    "PORTKILLER_PLUGIN_DIR": plugin.bundleURL.path,
                ],
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
            return try JSONDecoder().decode(Response.self, from: Data((output.isEmpty ? "{}" : output).utf8))
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
