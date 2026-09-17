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
        echo '{"items":[{"id":"web","title":"web","subtitle":"nginx","status":"running","port":8080,"url":"http://localhost:8080","fields":[{"label":"Image","value":"nginx"}],"actions":[{"id":"stop","title":"Stop","destructive":true}]}]}'
        ;;
      perform)
        echo "{\"message\":\"$(value action) $(value item) $PORTKILLER_API_VERSION\"}"
        ;;
      port-action)
        echo "{\"copy\":\"$(value port)\",\"refresh\":false}"
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
      "portActions": [
        { "id": "open", "title": "Open Project", "processes": ["node*", "bun"] },
        { "id": "inspect", "title": "Inspect", "ports": [5432] }
      ]
    }
    """

    func makeBundle(manifest: String = manifest, executable: String = "run", in directory: URL? = nil) throws -> URL {
        let root = directory ?? FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let bundle = root.appending(path: "Test-\(UUID().uuidString.prefix(6)).portkillerplugin")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try manifest.write(to: bundle.appending(path: "plugin.json"), atomically: true, encoding: .utf8)
        let script = bundle.appending(path: executable)
        try Self.script.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return bundle
    }

    @Test func decodesTheManifest() throws {
        let plugin = try PluginHost.load(makeBundle())
        #expect(plugin.id == "dev.example.test")
        #expect(plugin.manifest.summary == "A test plugin")
        #expect(plugin.manifest.items == PluginManifest.Items(title: "Containers", refreshInterval: 5))
        #expect(plugin.manifest.portActions?.count == 2)
    }

    @Test func matchesPortActionsByProcessAndPort() throws {
        let actions = try #require(try PluginHost.load(makeBundle()).manifest.portActions)
        #expect(actions[0].applies(toPort: 3000, processName: "node"))
        #expect(actions[0].applies(toPort: 3000, processName: "Bun"))
        #expect(!actions[0].applies(toPort: 3000, processName: "python3"))
        #expect(actions[1].applies(toPort: 5432, processName: "postgres"))
        #expect(!actions[1].applies(toPort: 5433, processName: "postgres"))
    }

    @Test func runsItemsAndActions() async throws {
        let plugin = try PluginHost.load(makeBundle())
        let items = try await PluginHost.items(of: plugin)
        #expect(items.map(\.id) == ["web"])
        #expect(items.first?.status == .running)
        #expect(items.first?.fields == [PluginField(label: "Image", value: "nginx")])

        let result = try await PluginHost.perform("stop", onItem: "web", in: plugin)
        #expect(result.message == "stop web 1")

        let listener = ListeningPort(port: 3000, addresses: ["127.0.0.1"], process: ProcessSnapshot(pid: 42, name: "node", commandLine: "node server.js", user: "me"))
        let portResult = try await PluginHost.perform("open", onPort: PluginPortContext(listener), in: plugin)
        #expect(portResult == PluginActionResult(copy: "3000", refresh: false))
    }

    @Test func reportsFailuresAndTimeouts() async throws {
        let plugin = try PluginHost.load(makeBundle())
        await #expect(throws: PluginError.failed(status: 3, message: "unknown command nope")) {
            try await PluginHost.call(plugin, command: "nope", request: PluginEmptyRequest(), as: PluginActionResult.self)
        }
        await #expect(throws: PluginError.timedOut) {
            try await PluginHost.call(plugin, command: "slow", request: PluginEmptyRequest(), as: PluginActionResult.self, timeout: .milliseconds(300))
        }
    }

    @Test func rejectsInvalidBundles() throws {
        #expect(throws: PluginError.invalidExecutable("The executable must be inside the plugin folder.")) {
            try PluginHost.load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""executable": "run""#, with: #""executable": "../run""#)))
        }
        #expect(throws: PluginError.unsupportedAPIVersion(2)) {
            try PluginHost.load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""apiVersion": 1"#, with: #""apiVersion": 2"#)))
        }
        #expect(throws: PluginError.invalidManifest("name is missing.")) {
            try PluginHost.load(makeBundle(manifest: Self.manifest.replacingOccurrences(of: #""name": "Test","#, with: "")))
        }
    }

    @Test func discoversPluginsAndSkipsDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        _ = try makeBundle(in: directory)
        _ = try makeBundle(in: directory)
        try FileManager.default.createDirectory(at: directory.appending(path: "Broken.portkillerplugin"), withIntermediateDirectories: true)
        let result = PluginHost.discover(in: directory)
        #expect(result.plugins.count == 1)
        #expect(result.failures.count == 2)
    }
}
