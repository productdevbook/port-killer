public import Foundation

public enum CloudflaredOutput {
    public enum NamedTunnelEvent: Sendable, Equatable {
        case connectionRegistered
        case connectionUnregistered
        case metricsPort(Int)
        case ingress([TunnelIngressRule])
    }

    public static func quickTunnelURL(in line: String) -> String? {
        line.firstMatch(of: /https:\/\/[a-z0-9-]+\.trycloudflare\.com/).map { String($0.output) }
    }

    public static func namedTunnelEvents(in line: String) -> [NamedTunnelEvent] {
        var events: [NamedTunnelEvent] = []
        if line.contains("Registered tunnel connection") {
            events.append(.connectionRegistered)
        } else if line.contains("Unregistered tunnel connection") {
            events.append(.connectionUnregistered)
        }
        if line.contains("Starting metrics server on"), let match = line.firstMatch(of: /127\.0\.0\.1:(\d+)/), let port = Int(match.1) {
            events.append(.metricsPort(port))
        }
        if line.contains("Updated to new configuration"), let rules = runtimeIngress(in: line) {
            events.append(.ingress(rules))
        }
        return events
    }

    static func runtimeIngress(in line: String) -> [TunnelIngressRule]? {
        guard let start = line.range(of: "config=\"") else { return nil }
        let remainder = line[start.upperBound...]
        guard let end = remainder.range(of: "\" version=") ?? remainder.range(of: "\"", options: .backwards) else { return nil }
        let json = remainder[..<end.lowerBound]
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        struct Configuration: Decodable {
            struct Rule: Decodable {
                var hostname: String?
                var path: String?
                var service: String?
            }
            var ingress: [Rule]
        }
        guard let configuration = try? JSONDecoder().decode(Configuration.self, from: Data(json.utf8)) else { return nil }
        return configuration.ingress.compactMap { rule in
            rule.service.map { TunnelIngressRule(hostname: rule.hostname, path: rule.path, service: $0) }
        }
    }
}

public struct Cloudflared: Sendable {
    public var executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    public static var configurationDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cloudflared", directoryHint: .isDirectory)
    }

    public static var isLoggedIn: Bool {
        FileManager.default.fileExists(atPath: configurationDirectory.appending(path: "cert.pem").path)
    }

    public static func quickTunnelArguments(port: Int, protocol transport: QuickTunnelProtocol) -> [String] {
        ["tunnel", "--url", "localhost:\(port)", "--protocol", transport.rawValue]
    }

    public static func namedTunnelArguments(name: String) -> [String] {
        ["tunnel", "--metrics", "127.0.0.1:0", "run", name]
    }

    public static let orphanedQuickTunnelPattern = "cloudflared.*tunnel.*--url"
}

public enum TunnelDiscovery {
    public struct LocalConfiguration: Sendable, Equatable {
        public var tunnel: String
        public var ingress: [TunnelIngressRule]
    }

    struct Credential {
        var id: String
        var path: String
    }

    struct RemoteTunnel {
        var id: String
        var name: String
        var createdAt: Date?
        var edgeConnections: [TunnelEdgeConnection]
    }

    public static func discover(executable: URL?, directory: URL = Cloudflared.configurationDirectory) async -> [DiscoveredTunnel] {
        var tunnels: [String: DiscoveredTunnel] = [:]
        for credential in credentials(in: directory) {
            tunnels[credential.id] = DiscoveredTunnel(id: credential.id, name: credential.id, credentialsPath: credential.path, edgeConnections: [], localIngress: [])
        }
        if let executable,
           let result = try? await CommandRunner.run(executable, ["--output", "json", "tunnel", "list"], environment: ["PATH": CommandLineTool.searchPath]),
           result.succeeded {
            for remote in parseTunnelList(Data(result.output.utf8)) {
                var tunnel = tunnels[remote.id] ?? DiscoveredTunnel(id: remote.id, name: remote.name, edgeConnections: [], localIngress: [])
                tunnel.name = remote.name
                tunnel.createdAt = remote.createdAt
                tunnel.edgeConnections = remote.edgeConnections
                tunnels[remote.id] = tunnel
            }
        }
        if let text = try? String(contentsOf: directory.appending(path: "config.yml"), encoding: .utf8),
           let configuration = parseConfiguration(text) {
            for (id, tunnel) in tunnels where tunnel.id == configuration.tunnel || tunnel.name == configuration.tunnel {
                tunnels[id]?.localIngress = configuration.ingress
            }
        }
        return tunnels.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func credentials(in directory: URL) -> [Credential] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            let stem = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", UUID(uuidString: stem) != nil else { return nil }
            struct File: Decodable {
                var TunnelID: String?
            }
            let identifier = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) }?.TunnelID ?? stem
            return Credential(id: identifier, path: url.path)
        }
    }

    static func parseTunnelList(_ data: Data) -> [RemoteTunnel] {
        guard let start = data.firstIndex(of: UInt8(ascii: "[")) else { return [] }
        struct Item: Decodable {
            struct Connection: Decodable {
                var id: String
                var colo_name: String
                var origin_ip: String?
                var opened_at: String?
                var is_pending_reconnect: Bool?
            }
            var id: String
            var name: String
            var created_at: String?
            var connections: [Connection]?
        }
        guard let items = try? JSONDecoder().decode([Item].self, from: data[start...]) else { return [] }
        return items.map { item in
            RemoteTunnel(
                id: item.id,
                name: item.name,
                createdAt: item.created_at.flatMap(parseDate),
                edgeConnections: (item.connections ?? []).map { connection in
                    TunnelEdgeConnection(
                        id: connection.id,
                        coloName: connection.colo_name,
                        originIP: connection.origin_ip ?? "",
                        openedAt: connection.opened_at.flatMap(parseDate),
                        isPendingReconnect: connection.is_pending_reconnect ?? false
                    )
                }
            )
        }
    }

    static func parseDate(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    public static func parseConfiguration(_ source: String) -> LocalConfiguration? {
        var tunnel: String?
        var rules: [TunnelIngressRule] = []
        var inIngress = false
        var hostname: String?
        var path: String?
        var service: String?

        func flush() {
            if let service { rules.append(TunnelIngressRule(hostname: hostname, path: path, service: service)) }
            hostname = nil
            path = nil
            service = nil
        }

        func apply(_ field: String) {
            if let value = value(of: "hostname", in: field) {
                hostname = value
            } else if let value = value(of: "path", in: field) {
                path = value
            } else if let value = value(of: "service", in: field) {
                service = value
            }
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                if inIngress {
                    flush()
                    inIngress = false
                }
                if let value = value(of: "tunnel", in: trimmed) {
                    tunnel = value
                } else if trimmed.hasPrefix("ingress:") {
                    inIngress = true
                }
                continue
            }
            guard inIngress else { continue }
            if trimmed.hasPrefix("- ") {
                flush()
                apply(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else {
                apply(trimmed)
            }
        }
        if inIngress { flush() }
        guard let tunnel else { return nil }
        return LocalConfiguration(tunnel: tunnel, ingress: rules)
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix("\(key):") else { return nil }
        let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
