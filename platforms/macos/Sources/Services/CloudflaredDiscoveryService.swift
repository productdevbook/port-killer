import Foundation

// MARK: - Discovery Service

/// Discovers persistent (named) Cloudflare tunnels from local cloudflared state.
///
/// Reads three sources:
///   1. `~/.cloudflared/<UUID>.json` — credentials files (gives us tunnel ID + AccountTag offline)
///   2. `cloudflared --output json tunnel list` — authoritative tunnel list with live edge connections
///   3. `~/.cloudflared/config.yml` — local ingress rules (may not exist for dashboard-managed tunnels)
actor CloudflaredDiscoveryService {
    /// Default cloudflared config directory.
    nonisolated var configDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cloudflared", isDirectory: true)
    }

    nonisolated var configFile: URL {
        configDirectory.appendingPathComponent("config.yml")
    }

    nonisolated var certFile: URL {
        configDirectory.appendingPathComponent("cert.pem")
    }

    /// Whether the user appears to have logged in via `cloudflared tunnel login`.
    nonisolated var isLoggedIn: Bool {
        FileManager.default.fileExists(atPath: certFile.path)
    }

    // MARK: - Public API

    /// Discover all named tunnels visible to the current user.
    ///
    /// Strategy:
    ///   - Always start with credentials files on disk (works offline).
    ///   - If cloudflared is available, augment with `tunnel list` (adds remote name + connections).
    ///   - Merge ingress rules from local `config.yml` if any tunnel name matches the `tunnel:` field.
    func discover(cloudflaredPath: String?) async -> [DiscoveredTunnel] {
        var byID: [String: DiscoveredTunnel] = [:]

        // 1. Local credentials files
        for cred in readCredentialsFiles() {
            byID[cred.tunnelID] = DiscoveredTunnel(
                tunnelID: cred.tunnelID,
                name: cred.tunnelID,  // fallback name; overwritten by list below
                createdAt: nil,
                credentialsPath: cred.path,
                edgeConnections: []
            )
        }

        // 2. `cloudflared tunnel list` (authoritative when reachable)
        if let cloudflaredPath = cloudflaredPath,
           let listed = await runTunnelList(cloudflaredPath: cloudflaredPath) {
            for remote in listed {
                if var existing = byID[remote.id] {
                    existing.name = remote.name
                    existing.createdAt = remote.createdAt
                    existing.edgeConnections = remote.connections
                    byID[remote.id] = existing
                } else {
                    byID[remote.id] = DiscoveredTunnel(
                        tunnelID: remote.id,
                        name: remote.name,
                        createdAt: remote.createdAt,
                        credentialsPath: nil,
                        edgeConnections: remote.connections
                    )
                }
            }
        }

        // 3. Local ingress (config.yml). The `tunnel:` field references either name or UUID.
        if let localConfig = readLocalConfig() {
            let tunnelRef = localConfig.tunnelRef
            for key in byID.keys {
                let t = byID[key]!
                if t.tunnelID == tunnelRef || t.name == tunnelRef {
                    var updated = t
                    updated.localIngress = localConfig.ingress
                    byID[key] = updated
                }
            }
        }

        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Credentials Files

    private nonisolated func readCredentialsFiles() -> [LocalCredential] {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: configDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [LocalCredential] = []
        for url in entries where url.pathExtension == "json" {
            // Tunnel credentials filename is the UUID itself.
            let stem = url.deletingPathExtension().lastPathComponent
            guard isUUID(stem) else { continue }
            // Sanity-check by reading the file. We accept either {TunnelID: ...} or just trust the filename.
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let id = (json["TunnelID"] as? String) ?? stem
                result.append(LocalCredential(tunnelID: id, path: url.path))
            } else {
                result.append(LocalCredential(tunnelID: stem, path: url.path))
            }
        }
        return result
    }

    private nonisolated func isUUID(_ s: String) -> Bool {
        UUID(uuidString: s) != nil
    }

    // MARK: - Remote List

    private func runTunnelList(cloudflaredPath: String) async -> [RemoteTunnel]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cloudflaredPath)
        process.arguments = ["--output", "json", "tunnel", "list"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        // Read output before waiting to avoid pipe deadlock on large outputs.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return RemoteTunnel.parseList(outData)
    }

    // MARK: - Local Config

    private nonisolated func readLocalConfig() -> LocalConfig? {
        guard let raw = try? String(contentsOf: configFile, encoding: .utf8) else { return nil }
        return parseConfigYAML(raw)
    }

    /// Tiny purpose-built parser for the subset of cloudflared `config.yml` we need.
    /// We only extract the top-level `tunnel:` value and the `ingress:` list of
    /// `{hostname, service}` pairs. This avoids pulling in a YAML dependency.
    nonisolated func parseConfigYAML(_ source: String) -> LocalConfig? {
        var tunnelRef: String?
        var rules: [CloudflareTunnelIngressRule] = []
        var inIngress = false
        var currentHostname: String?
        var currentPath: String?
        var currentService: String?

        func flushRule() {
            if let service = currentService {
                rules.append(CloudflareTunnelIngressRule(hostname: currentHostname, path: currentPath, service: service))
            }
            currentHostname = nil
            currentPath = nil
            currentService = nil
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // Strip comments.
            let withoutComment: String
            if let hashIdx = line.firstIndex(of: "#") {
                withoutComment = String(line[..<hashIdx])
            } else {
                withoutComment = line
            }
            let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Top-level keys (no leading whitespace).
            let isTopLevel = !withoutComment.hasPrefix(" ") && !withoutComment.hasPrefix("\t")

            if isTopLevel {
                // Leaving the ingress section.
                if inIngress {
                    flushRule()
                    inIngress = false
                }
                if let value = stripKey("tunnel", from: trimmed) {
                    tunnelRef = value
                } else if trimmed.hasPrefix("ingress:") {
                    inIngress = true
                }
                continue
            }

            guard inIngress else { continue }

            if trimmed.hasPrefix("- ") {
                // New rule begins; flush the previous.
                flushRule()
                let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                applyIngressField(afterDash, hostname: &currentHostname, path: &currentPath, service: &currentService)
            } else {
                applyIngressField(trimmed, hostname: &currentHostname, path: &currentPath, service: &currentService)
            }
        }
        if inIngress { flushRule() }

        guard let tunnelRef = tunnelRef else { return nil }
        return LocalConfig(tunnelRef: tunnelRef, ingress: rules)
    }

    private nonisolated func applyIngressField(_ s: String, hostname: inout String?, path: inout String?, service: inout String?) {
        if let value = stripKey("hostname", from: s) {
            hostname = value
        } else if let value = stripKey("path", from: s) {
            path = value
        } else if let value = stripKey("service", from: s) {
            service = value
        }
    }

    private nonisolated func stripKey(_ key: String, from line: String) -> String? {
        let prefix = "\(key):"
        guard line.hasPrefix(prefix) else { return nil }
        let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return stripQuotes(value)
    }

    private nonisolated func stripQuotes(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        let first = s.first!
        let last = s.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}

// MARK: - Aggregated Discovery Result

struct DiscoveredTunnel: Sendable, Hashable {
    let tunnelID: String
    var name: String
    var createdAt: Date?
    var credentialsPath: String?
    var edgeConnections: [CloudflareTunnelEdgeConnection]
    var localIngress: [CloudflareTunnelIngressRule] = []
}

// MARK: - Internal Helpers

private struct LocalCredential: Sendable {
    let tunnelID: String
    let path: String
}

struct LocalConfig: Sendable {
    let tunnelRef: String
    let ingress: [CloudflareTunnelIngressRule]
}

private struct RemoteTunnel: Sendable {
    let id: String
    let name: String
    let createdAt: Date?
    let connections: [CloudflareTunnelEdgeConnection]

    static func parseList(_ data: Data) -> [RemoteTunnel]? {
        // cloudflared may prepend a `--output json` warning line; find the first `[`.
        guard let firstBracket = data.firstIndex(of: UInt8(ascii: "[")) else { return nil }
        let jsonData = data.subdata(in: firstBracket..<data.endIndex)
        guard let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFallback = ISO8601DateFormatter()

        return arr.compactMap { dict -> RemoteTunnel? in
            guard let id = dict["id"] as? String, let name = dict["name"] as? String else { return nil }
            let createdAt: Date? = {
                guard let s = dict["created_at"] as? String else { return nil }
                return iso.date(from: s) ?? isoFallback.date(from: s)
            }()
            let conns = (dict["connections"] as? [[String: Any]] ?? []).compactMap { c -> CloudflareTunnelEdgeConnection? in
                guard let id = c["id"] as? String, let colo = c["colo_name"] as? String else { return nil }
                let originIP = (c["origin_ip"] as? String) ?? ""
                let openedAt: Date? = {
                    guard let s = c["opened_at"] as? String else { return nil }
                    return iso.date(from: s) ?? isoFallback.date(from: s)
                }()
                let pending = (c["is_pending_reconnect"] as? Bool) ?? false
                return CloudflareTunnelEdgeConnection(
                    id: id,
                    coloName: colo,
                    originIP: originIP,
                    openedAt: openedAt,
                    isPendingReconnect: pending
                )
            }
            return RemoteTunnel(id: id, name: name, createdAt: createdAt, connections: conns)
        }
    }
}
