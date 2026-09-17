public import Foundation

public struct PortForwardConfiguration: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var namespace: String
    public var service: String
    public var localPort: Int
    public var remotePort: Int
    public var proxyPort: Int?
    public var isEnabled: Bool
    public var autoReconnect: Bool
    public var useDirectExec: Bool
    public var notifyOnConnect: Bool
    public var notifyOnDisconnect: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        namespace: String,
        service: String,
        localPort: Int,
        remotePort: Int,
        proxyPort: Int? = nil,
        isEnabled: Bool = true,
        autoReconnect: Bool = true,
        useDirectExec: Bool = true,
        notifyOnConnect: Bool = true,
        notifyOnDisconnect: Bool = true
    ) {
        self.id = id
        self.name = name
        self.namespace = namespace
        self.service = service
        self.localPort = localPort
        self.remotePort = remotePort
        self.proxyPort = proxyPort
        self.isEnabled = isEnabled
        self.autoReconnect = autoReconnect
        self.useDirectExec = useDirectExec
        self.notifyOnConnect = notifyOnConnect
        self.notifyOnDisconnect = notifyOnDisconnect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        namespace = try container.decode(String.self, forKey: .namespace)
        service = try container.decode(String.self, forKey: .service)
        localPort = try container.decode(Int.self, forKey: .localPort)
        remotePort = try container.decode(Int.self, forKey: .remotePort)
        proxyPort = try container.decodeIfPresent(Int.self, forKey: .proxyPort)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        autoReconnect = try container.decodeIfPresent(Bool.self, forKey: .autoReconnect) ?? true
        useDirectExec = try container.decodeIfPresent(Bool.self, forKey: .useDirectExec) ?? true
        notifyOnConnect = try container.decodeIfPresent(Bool.self, forKey: .notifyOnConnect) ?? true
        notifyOnDisconnect = try container.decodeIfPresent(Bool.self, forKey: .notifyOnDisconnect) ?? true
    }

    public var effectivePort: Int {
        proxyPort ?? localPort
    }

    public var usesDirectExec: Bool {
        proxyPort != nil && useDirectExec
    }

    public var target: String {
        "\(namespace)/\(service)"
    }

    public var localURL: URL? {
        URL(string: "http://localhost:\(effectivePort)")
    }

    public static func suggestedLocalPort(forRemotePort remotePort: Int) -> Int {
        switch remotePort {
        case 80: 8080
        case 443: 8443
        case ...1024: remotePort + 8000
        default: remotePort
        }
    }

    public static func placeholder() -> PortForwardConfiguration {
        PortForwardConfiguration(name: "New Connection", namespace: "default", service: "service-name", localPort: 8080, remotePort: 80)
    }
}

public enum PortForwardPlan {
    public static func kubectlArguments(_ configuration: PortForwardConfiguration) -> [String] {
        [
            "port-forward",
            "-n", configuration.namespace,
            "svc/\(configuration.service)",
            "\(configuration.localPort):\(configuration.remotePort)",
            "--address=127.0.0.1",
        ]
    }

    public static func proxyArguments(listenPort: Int, targetPort: Int) -> [String] {
        ["TCP-LISTEN:\(listenPort),fork,reuseaddr", "TCP:127.0.0.1:\(targetPort)"]
    }

    public static func directExecArguments(listenPort: Int, script: URL) -> [String] {
        ["TCP-LISTEN:\(listenPort),fork,reuseaddr", "EXEC:\(script.path)"]
    }

    public static func directExecScript(_ configuration: PortForwardConfiguration, kubectl: URL, socat: URL) -> String {
        """
        #!/bin/bash
        export PATH=\(shellQuoted(CommandLineTool.searchPath))
        PORT=$((30000 + ($$ % 30000)))
        while /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null; do
            PORT=$((PORT + 1))
        done
        \(shellQuoted(kubectl.path)) port-forward -n \(shellQuoted(configuration.namespace)) \(shellQuoted("svc/\(configuration.service)")) "$PORT:\(configuration.remotePort)" --address=127.0.0.1 >/dev/null 2>&1 &
        KUBECTL_PID=$!
        trap 'kill $KUBECTL_PID 2>/dev/null' EXIT
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
            /usr/bin/nc -z 127.0.0.1 $PORT 2>/dev/null && break
            sleep 0.25
        done
        \(shellQuoted(socat.path)) - "TCP:127.0.0.1:$PORT"
        """
    }

    public static func writeDirectExecScript(_ configuration: PortForwardConfiguration, kubectl: URL, socat: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PortKiller", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appending(path: "forward-\(configuration.id.uuidString).sh")
        try directExecScript(configuration, kubectl: kubectl, socat: socat).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum PortForwardOutput {
    public static func isError(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return ["error", "failed", "unable to", "connection refused", "lost connection", "an error occurred"].contains(where: lowercased.contains)
    }

    public static func isReady(_ line: String) -> Bool {
        line.hasPrefix("Forwarding from 127.0.0.1:")
    }

    public static func conflictingPort(in line: String) -> Int? {
        guard line.lowercased().contains("address already in use") else { return nil }
        for pattern in [/127\.0\.0\.1:(\d+)/, /0\.0\.0\.0:(\d+)/] {
            if let match = line.firstMatch(of: pattern), let port = Int(match.1) {
                return port
            }
        }
        return nil
    }
}
