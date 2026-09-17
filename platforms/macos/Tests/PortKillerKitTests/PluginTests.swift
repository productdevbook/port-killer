import Foundation
import Testing
@testable import PortKillerKit

struct PluginTests {
    static let script = #"""
    #!/bin/bash
    input=$(cat)
    value() {
      printf '%s' "$input" | sed -n 's/.*"'"$1"'":"\{0,1\}\([^",}]*\).*/\1/p'
    }
    case "$1" in
      items)
        if [ "$PORTKILLER_SETTING_MODE_NAME" = duplicate ]; then
          echo '{"items":[{"id":"web","title":"web"},{"id":"web","title":"web again"}]}'
        else
          echo '{"items":[{"id":"web","title":"web","subtitle":"nginx","status":"running","port":8080,"targetPorts":[3000],"url":"http://localhost:8080","fields":[{"label":"Image","value":"nginx"}],"actions":[{"id":"stop","title":"Stop","destructive":true,"confirmation":"Stop web?","inputs":[{"id":"grace","label":"Grace Period","type":"number","default":10}]}]}]}'
        fi
        ;;
      perform)
        echo "{\"message\":\"$(value action) $(value item) $(value grace) $PORTKILLER_API_VERSION\"}"
        ;;
      port-action)
        echo "port action log" >&2
        if [ -n "$(value method)" ]; then
          echo "{\"details\":{\"title\":\"$(value path)\",\"fields\":[{\"label\":\"Method\",\"value\":\"$(value method)\"},{\"label\":\"Connection\",\"value\":\"$(value connection)\"}],\"text\":\"port $(value port)\"}}"
        else
          echo "{\"copy\":\"$(value port)\",\"refresh\":false}"
        fi
        ;;
      env)
        echo "{\"message\":\"$PORTKILLER_SETTING_TOKEN|$PORTKILLER_SETTING_MODE_NAME|$PORTKILLER_DATA_DIR\"}"
        ;;
      slow)
        sleep 5
        ;;
      *)
        echo "unknown command $1" >&2
        exit 3
        ;;
    esac
    """#

    static let manifest = """
    {
      "apiVersion": 1,
      "id": "dev.example.test",
      "name": "Test",
      "version": "1.0.0",
      "description": "A test plugin",
      "icon": "shippingbox",
      "executable": "run",
      "items": { "title": "Containers", "refreshInterval": 5 },
      "settings": [
        { "id": "token", "label": "Token", "type": "secret", "required": true },
        { "id": "mode-name", "label": "Mode", "type": "choice", "options": ["normal", "duplicate"] },
        { "id": "verbose", "label": "Verbose", "type": "toggle", "default": true }
      ],
      "portActions": [
        { "id": "open", "title": "Open Project", "processes": ["node*", "bun"] },
        {
          "id": "inspect",
          "title": "Inspect",
          "description": "Looks inside the database.",
          "ports": [5432],
          "confirmation": "Inspect the database?",
          "inputs": [
            { "id": "method", "label": "Method", "type": "choice", "options": ["GET", "POST"] },
            { "id": "path", "label": "Path", "default": "/", "required": true }
          ]
        }
      ]
    }
    """

    let dataRoot = FileManager.default.temporaryDirectory.appending(path: "PluginData-\(UUID().uuidString)")

    func makeBundle(manifest: String = manifest, executable: String = "run", name: String? = nil, in directory: URL? = nil) throws -> URL {
        let root = directory ?? FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = root.appending(path: "\(name ?? "Test-\(UUID().uuidString.prefix(6))").portkillerplugin")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try manifest.write(to: bundle.appending(path: "plugin.json"), atomically: true, encoding: .utf8)
        let script = bundle.appending(path: executable)
        try Self.script.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bundle
    }

    func load(_ bundle: URL) throws -> Plugin {
        try PluginHost.load(bundle, dataRoot: dataRoot)
    }

    @Test func decodesTheManifest() throws {
        let plugin = try load(makeBundle())
        #expect(plugin.id == "dev.example.test")
        #expect(plugin.manifest.summary == "A test plugin")
        #expect(plugin.manifest.items == PluginManifest.Items(title: "Containers", refreshInterval: 5))
        #expect(plugin.manifest.portActions?.count == 2)
        #expect(plugin.manifest.settings?.map(\.kind) == [.secret, .choice, .toggle])
        #expect(plugin.manifest.settings?.last?.defaultValue == "true")
        let inspect = try #require(plugin.manifest.portActions?.last)
        #expect(inspect.confirmation == "Inspect the database?")
        #expect(inspect.summary == "Looks inside the database.")
        #expect(inspect.inputs?.map(\.id) == ["method", "path"])
        #expect(plugin.dataURL == dataRoot.appending(path: "dev.example.test", directoryHint: .isDirectory))
    }

    @Test func matchesPortActionsByProcessAndPort() throws {
        let actions = try #require(try load(makeBundle()).manifest.portActions)
        #expect(actions[0].applies(toPort: 3000, processName: "node"))
        #expect(actions[0].applies(toPort: 3000, processName: "Bun"))
        #expect(!actions[0].applies(toPort: 3000, processName: "python3"))
        #expect(actions[1].applies(toPort: 5432, processName: "postgres"))
        #expect(!actions[1].applies(toPort: 5433, processName: "postgres"))
    }

    @Test func runsItemsAndActions() async throws {
        let plugin = try load(makeBundle())
        let items = try await PluginHost.items(of: plugin)
        #expect(items.map(\.id) == ["web"])
        #expect(items.first?.status == .running)
        #expect(items.first?.targetPorts == [3000])
        #expect(items.first?.fields == [PluginField(label: "Image", value: "nginx")])
        let stop = try #require(items.first?.actions?.first)
        #expect(stop.confirmation == "Stop web?")
        #expect(stop.inputs?.first?.defaultValue == "10")

        let result = try await PluginHost.perform("stop", onItem: "web", inputs: ["grace": "30"], in: plugin)
        #expect(result.message == "stop web 30 1")

        let listener = ListeningPort(port: 3000, addresses: ["127.0.0.1"], process: ProcessSnapshot(pid: 42, name: "node", commandLine: "node server.js", user: "me"))
        let portResult = try await PluginHost.perform("open", onPort: PluginPortContext(listener), in: plugin)
        #expect(portResult == PluginActionResult(copy: "3000", refresh: false, log: "port action log"))

        let connection = UUID()
        let detailed = try await PluginHost.perform("inspect", onPort: PluginPortContext(listener), inputs: ["method": "POST", "path": "/users"], connection: connection, in: plugin)
        #expect(detailed.details == PluginDetails(
            title: "/users",
            fields: [PluginField(label: "Method", value: "POST"), PluginField(label: "Connection", value: connection.uuidString)],
            text: "port 3000"
        ))
    }

    @Test func passesSettingsAndTheDataDirectory() async throws {
        let plugin = try load(makeBundle())
        let result = try await PluginHost.call(plugin, command: "env", request: PluginEmptyRequest(), as: PluginActionResult.self, settings: ["token": "s3cret"])
        #expect(result.message == "s3cret|normal|\(plugin.dataURL.path)")
        #expect(FileManager.default.fileExists(atPath: plugin.dataURL.path))
        let environment = PluginHost.environment(for: plugin, settings: ["mode-name": "duplicate"])
        #expect(environment["PORTKILLER_SETTING_MODE_NAME"] == "duplicate")
        #expect(environment["PORTKILLER_SETTING_VERBOSE"] == "true")
        #expect(environment["PORTKILLER_SETTING_TOKEN"] == "")
    }

    @Test func rejectsItemsWithRepeatedIDs() async throws {
        let plugin = try load(makeBundle())
        await #expect(throws: PluginError.unreadableResponse("More than one item has the id web.")) {
            try await PluginHost.items(of: plugin, settings: ["mode-name": "duplicate"])
        }
    }

    @Test func validatesInputValues() {
        let method = PluginInput(id: "method", label: "Method", type: .choice, options: ["GET", "POST"])
        let path = PluginInput(id: "path", label: "Path", defaultValue: "/", required: true)
        let count = PluginInput(id: "count", label: "Count", type: .number)
        let verbose = PluginInput(id: "verbose", label: "Verbose", type: .toggle, required: true)
        let inputs = [method, path, count, verbose]

        #expect(method.problem(with: "PUT") == "Method must be one of GET, POST.")
        #expect(path.problem(with: "  ") == "Path is required.")
        #expect(count.problem(with: "") == nil)
        #expect(count.problem(with: "ten") == "Count must be a number.")
        #expect(verbose.problem(with: "") == nil)
        #expect(verbose.problem(with: "yes") == "Verbose must be true or false.")
        #expect(verbose.environmentName == "PORTKILLER_SETTING_VERBOSE")

        #expect(inputs.values() == ["method": "GET", "path": "/", "count": "", "verbose": "false"])
        #expect(inputs.values(remembered: ["method": "POST", "count": "nope"]) == ["method": "POST", "path": "/", "count": "", "verbose": "false"])
        #expect(inputs.problems(in: ["method": "DELETE", "path": "", "count": "1"]) == ["Method must be one of GET, POST.", "Path is required."])
    }

    @Test func rejectsInvalidInputDefinitions() throws {
        let noOptions = Self.manifest.replacingOccurrences(of: #""options": ["GET", "POST"] "#, with: "")
        #expect(throws: PluginError.invalidManifest("Port action inspect input method is a choice without options.")) {
            try load(makeBundle(manifest: noOptions))
        }
        let repeated = Self.manifest.replacingOccurrences(of: #""id": "path""#, with: #""id": "method""#)
        #expect(throws: PluginError.invalidManifest("Port action inspect has more than one input with the id method.")) {
            try load(makeBundle(manifest: repeated))
        }
        let badSetting = Self.manifest.replacingOccurrences(of: #""id": "token""#, with: #""id": "api token""#)
        #expect(throws: PluginError.invalidManifest("settings has an input whose id isn't made of letters, digits, dashes and underscores.")) {
            try load(makeBundle(manifest: badSetting))
        }
        let badDefault = Self.manifest.replacingOccurrences(of: #""default": true"#, with: #""default": "maybe""#)
        #expect(throws: PluginError.invalidManifest("settings input verbose has a default that doesn't fit its type.")) {
            try load(makeBundle(manifest: badDefault))
        }
    }

    @Test func reportsFailuresAndTimeouts() async throws {
        let plugin = try load(makeBundle())
        await #expect(throws: PluginError.failed(status: 3, message: "unknown command nope")) {
            try await PluginHost.call(plugin, command: "nope", request: PluginEmptyRequest(), as: PluginActionResult.self)
        }
        await #expect(throws: PluginError.timedOut) {
            try await PluginHost.call(plugin, command: "slow", request: PluginEmptyRequest(), as: PluginActionResult.self, timeout: .milliseconds(300))
        }
    }

    @Test func rejectsInvalidBundles() throws {
        #expect(throws: PluginError.invalidExecutable("The executable must be inside the plugin folder.")) {
            try load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""executable": "run""#, with: #""executable": "../run""#)))
        }
        #expect(throws: PluginError.unsupportedAPIVersion(2)) {
            try load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""apiVersion": 1"#, with: #""apiVersion": 2"#)))
        }
        #expect(throws: PluginError.invalidManifest("name is missing.")) {
            try load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""name": "Test","#, with: "")))
        }
    }

    @Test func discoversPluginsAndSkipsDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        _ = try makeBundle(in: directory)
        _ = try makeBundle(in: directory)
        try FileManager.default.createDirectory(at: directory.appending(path: "Broken.portkillerplugin"), withIntermediateDirectories: true)
        let result = PluginHost.discover(in: directory, dataRoot: dataRoot)
        #expect(result.plugins.count == 1)
        #expect(result.failures.count == 2)
    }

    @Test func installsAndReplacesPlugins() throws {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appending(path: "Plugins-\(UUID().uuidString)")

        let first = try makeBundle(name: "First")
        let installed = try PluginHost.install(first, into: directory, dataRoot: dataRoot)
        #expect(installed.bundleURL.lastPathComponent == "First.portkillerplugin")
        #expect(manager.isExecutableFile(atPath: installed.executableURL.path))
        #expect(manager.fileExists(atPath: first.path))

        let upgrade = try makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""version": "1.0.0""#, with: #""version": "2.0.0""#), name: "Renamed")
        let replaced = try PluginHost.install(upgrade, into: directory, dataRoot: dataRoot)
        #expect(replaced.manifest.version == "2.0.0")
        let names = try manager.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(names == ["Renamed.portkillerplugin"])

        #expect(throws: PluginError.installFailed("Choose a folder whose name ends in .portkillerplugin.")) {
            try PluginHost.install(manager.temporaryDirectory, into: directory, dataRoot: dataRoot)
        }
        let broken = try makeBundle(manifest: "{}", name: "Broken")
        #expect(throws: PluginError.self) {
            try PluginHost.install(broken, into: directory, dataRoot: dataRoot)
        }
        #expect(try manager.contentsOfDirectory(atPath: directory.path).sorted() == ["Renamed.portkillerplugin"])
        #expect(try PluginHost.install(directory.appending(path: "Renamed.portkillerplugin"), into: directory, dataRoot: dataRoot).manifest.version == "2.0.0")
    }

    @Test func tracksRunsAndTheirResults() {
        var activity = PluginActivity(limit: 3)
        let start = Date(timeIntervalSince1970: 1000)
        let first = activity.start(PluginRun(pluginID: "http", actionID: "get", title: "Send GET Request", target: .port(3000), started: start))
        #expect(activity.isRunning(plugin: "http", action: "get", target: .port(3000)))
        #expect(!activity.isRunning(plugin: "http", action: "get", target: .port(4000)))
        #expect(activity.run(first)?.summary == "Running…")

        activity.finish(first, as: .succeeded(PluginActionResult(message: "200 OK")), at: start.addingTimeInterval(0.25))
        #expect(activity.run(first)?.summary == "200 OK")
        #expect(activity.run(first)?.duration == .milliseconds(250))
        #expect(!activity.isRunning(plugin: "http", action: "get", target: .port(3000)))

        let second = activity.start(PluginRun(pluginID: "http", actionID: "get", title: "Send GET Request", target: .port(4000)))
        activity.finish(second, as: .failed("No response"))
        #expect(activity.latest(plugin: "http", action: "get")?.id == second)
        #expect(activity.run(second)?.summary == "No response")
        activity.start(PluginRun(pluginID: "docker", actionID: "logs", title: "Show Logs", target: .item("web")))
        #expect(activity.runs(for: .port(3000)).map(\.id) == [first])
        #expect(activity.runs(for: .item("web"), plugin: "http").isEmpty)

        activity.start(PluginRun(pluginID: "http", actionID: "details", title: "Details", target: .item("web"), started: start))
        #expect(activity.runs.count == 3)
        #expect(activity.run(first) == nil)

        activity.removeRuns(of: "http")
        #expect(activity.runs.map(\.title) == ["Details", "Show Logs"])
        activity.finish(UUID(), as: .failed("ignored"))
        #expect(activity.runs.count == 2)
    }
}
