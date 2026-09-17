#if os(macOS)
import Foundation
import Network
import Synchronization
import Testing
@testable import PortKillerKit

@Suite(.serialized)
struct ExamplePluginTests {
    let examples = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appending(path: "Plugins")
    let dataRoot = FileManager.default.temporaryDirectory.appending(path: "ExamplePluginData-\(UUID().uuidString)")

    func context(port: Int, pid: Int32 = 1, process: String = "node") -> PluginPortContext {
        PluginPortContext(ListeningPort(port: port, addresses: ["127.0.0.1"], process: ProcessSnapshot(pid: pid, name: process)))
    }

    @Test func examplesLoad() throws {
        let result = PluginHost.discover(in: examples, dataRoot: dataRoot)
        #expect(result.failures.isEmpty)
        #expect(result.plugins.map(\.id) == ["dev.portkiller.docker", "dev.portkiller.http-requests", "dev.portkiller.open-in-editor"])
        let editor = try #require(result.plugins.last)
        #expect(PluginHost.environment(for: editor, settings: [:])["PORTKILLER_SETTING_EDITOR"] == "Visual Studio Code")
    }

    @Test func openInEditorExplainsAMissingProcess() async throws {
        let plugin = try PluginHost.load(examples.appending(path: "OpenInEditor.portkillerplugin"), dataRoot: dataRoot)
        await #expect(throws: PluginError.failed(status: 1, message: "Couldn't find the folder process 999999 runs from.")) {
            try await PluginHost.perform("code", onPort: context(port: 3000, pid: 999_999), in: plugin)
        }
    }

    @Test func httpRequestsSendsRequests() async throws {
        let server = try EchoServer()
        let port = try await server.start()
        defer { server.stop() }
        let plugin = try PluginHost.load(examples.appending(path: "HTTPRequests.portkillerplugin"), dataRoot: dataRoot)
        let target = context(port: port)
        #expect(plugin.manifest.items == nil)
        #expect(plugin.manifest.portActions?.map(\.id) == ["send"])

        let get = try await PluginHost.perform("send", onPort: target, inputs: ["method": "GET", "path": "/"], in: plugin)
        #expect(get.message?.hasPrefix("GET localhost:\(port)/ → 200 · ") == true)
        #expect(get.details?.title == "GET localhost:\(port)/")
        #expect(get.details?.fields?.first == PluginField(label: "Status", value: "HTTP/1.1 200 OK"))
        #expect(get.details?.fields?.contains(PluginField(label: "X-Test", value: "echo")) == true)
        #expect(get.details?.fields?.last == PluginField(label: "curl", value: "curl -X GET 'http://localhost:\(port)/'"))
        #expect(try echo(get)["method"] == "GET")

        let request = [
            "method": "POST",
            "path": "users?role=admin",
            "headers": "Content-Type: application/json\nX-Extra: \"quoted\"",
            "body": #"{"name": "Ada", "note": "line\nbreak"}"#,
        ]
        let post = try await PluginHost.perform("send", onPort: target, inputs: request, node: UUID(), in: plugin)
        #expect(post.message?.hasPrefix("POST localhost:\(port)/users?role=admin → 201 · ") == true)
        let posted = try echo(post)
        #expect(posted["path"] == "/users?role=admin")
        #expect(posted["body"] == request["body"])
        #expect(posted["content-type"] == "application/json")
        #expect(posted["x-extra"] == "\"quoted\"")
        #expect(post.details?.fields?.last == PluginField(
            label: "curl",
            value: #"curl -X POST 'http://localhost:\#(port)/users?role=admin' -H 'Content-Type: application/json' -H 'X-Extra: "quoted"' --data-binary '{"name": "Ada", "note": "line\nbreak"}'"#
        ))

        let missing = try await PluginHost.perform("send", onPort: target, inputs: ["method": "GET", "path": "/missing"], in: plugin)
        #expect(missing.message?.hasPrefix("GET localhost:\(port)/missing → 404 · ") == true)
    }

    @Test func httpRequestsExplainsPortsThatArentWebServers() async throws {
        let plugin = try PluginHost.load(examples.appending(path: "HTTPRequests.portkillerplugin"), dataRoot: dataRoot)
        let closed = try await EchoServer.unusedPort()
        do {
            _ = try await PluginHost.perform("send", onPort: context(port: closed), inputs: ["method": "GET", "path": "/"], in: plugin)
            Issue.record("A closed port answered.")
        } catch {
            guard case .failed(1, let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.hasPrefix("Port \(closed) didn't answer HTTP or HTTPS, so it may not be a web server."))
        }
    }

    private func echo(_ result: PluginActionResult) throws -> [String: String] {
        let text = try #require(result.details?.text)
        return try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
    }
}

final class EchoServer: Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "EchoServer")

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    static func unusedPort() async throws -> Int {
        let server = try EchoServer()
        let port = try await server.start()
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        return port
    }

    func start() async throws -> Int {
        let queue = queue
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.receive(on: connection, buffer: Data())
        }
        let started = Mutex(false)
        return try await withCheckedThrowingContinuation { continuation in
            let listener = listener
            listener.stateUpdateHandler = { state in
                let resume: Bool = switch state {
                case .ready, .failed: started.withLock { wasStarted in
                    defer { wasStarted = true }
                    return !wasStarted
                }
                default: false
                }
                guard resume else { return }
                if case .failed(let error) = state {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: Int(listener.port?.rawValue ?? 0))
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let response = response(to: buffer) {
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private static func response(to buffer: Data) -> Data? {
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let requestLine = head.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }
        var echo = ["method": String(requestLine[0]), "path": String(requestLine[1])]
        for line in head.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            echo[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(echo["content-length"] ?? "") ?? 0
        let body = buffer[end.upperBound...]
        guard body.count >= length else { return nil }
        echo["body"] = String(decoding: body.prefix(length), as: UTF8.self)
        let status = echo["path"] == "/missing" ? "404 Not Found" : echo["method"] == "POST" ? "201 Created" : "200 OK"
        let payload = (try? JSONEncoder().encode(echo)) ?? Data()
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nX-Test: echo\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        return Data(header.utf8) + payload
    }
}
#endif
