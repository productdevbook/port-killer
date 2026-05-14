import Foundation

// MARK: - Port Exposure

/// A single (hostname, tunnel) pair exposing a local port through cloudflared.
struct PortExposure: Hashable, Sendable {
    let hostname: String
    let publicURL: String
    let tunnelName: String
    let tunnelID: String
}

// MARK: - Named Tunnel Manager

/// Manages discovery and lifecycle of persistent (named) Cloudflare tunnels.
///
/// Unlike `TunnelManager` (Quick Tunnels — ephemeral `*.trycloudflare.com` URLs), this
/// works with tunnels created via `cloudflared tunnel create`, identified by a stable
/// UUID, and run via `cloudflared tunnel run <name>`.
@Observable
@MainActor
final class NamedTunnelManager {
    /// Discovered tunnels, keyed implicitly by `tunnelID`.
    var tunnels: [NamedCloudflareTunnel] = []
    var isDiscovering: Bool = false
    var hasDiscovered: Bool = false

    private let cloudflaredService: CloudflaredService
    private let discoveryService: CloudflaredDiscoveryService
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        cloudflaredService: CloudflaredService,
        discoveryService: CloudflaredDiscoveryService = CloudflaredDiscoveryService()
    ) {
        self.cloudflaredService = cloudflaredService
        self.discoveryService = discoveryService
    }

    deinit {
        refreshTask?.cancel()
    }

    /// Start best-effort discovery while the Cloudflare Tunnels UI is visible.
    ///
    /// We avoid doing this from app launch because `cloudflared tunnel list` can hit
    /// the user's Cloudflare account, and that should only happen when the user
    /// opens tunnel management UI or explicitly refreshes.
    func startRefreshing() {
        discoverIfNeeded()
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self = self else { return }
                if self.isDiscovering { continue }
                await self.discoverAsync()
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Computed

    var runningCount: Int {
        tunnels.filter { $0.status == .running }.count
    }

    var isLoggedIn: Bool {
        discoveryService.isLoggedIn
    }

    /// All public hostnames exposed for a given local port across currently running tunnels.
    /// Returns an empty array if no running tunnel maps to that port.
    func exposures(for localPort: Int) -> [PortExposure] {
        var result: [PortExposure] = []
        for tunnel in tunnels where tunnel.status == .running {
            for rule in tunnel.ingressRules {
                guard rule.localPort == localPort,
                      let hostname = rule.hostname,
                      let publicURL = rule.publicURL else { continue }
                result.append(PortExposure(
                    hostname: hostname,
                    publicURL: publicURL,
                    tunnelName: tunnel.name,
                    tunnelID: tunnel.tunnelID
                ))
            }
        }
        return result
    }

    // MARK: - Discovery

    func discover(force: Bool = false) {
        guard force || !isDiscovering else { return }
        Task { await discoverAsync() }
    }

    func discoverIfNeeded() {
        guard !hasDiscovered else { return }
        discover()
    }

    func discoverAsync() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer {
            isDiscovering = false
            hasDiscovered = true
        }

        let cloudflaredPath = cloudflaredService.cloudflaredPath
        let discovered = await discoveryService.discover(cloudflaredPath: cloudflaredPath)

        // Merge with existing tunnels, preserving runtime state for ones we're currently running.
        var existingByID: [String: NamedCloudflareTunnel] = [:]
        for t in tunnels { existingByID[t.tunnelID] = t }

        var merged: [NamedCloudflareTunnel] = []
        for d in discovered {
            let tunnel: NamedCloudflareTunnel
            if let existing = existingByID[d.tunnelID] {
                tunnel = existing
                tunnel.credentialsPath = d.credentialsPath
                tunnel.edgeConnections = d.edgeConnections
                // Only overwrite ingress from config.yml if we haven't picked up a runtime version.
                if tunnel.ingressSource != .runtimeLog, !d.localIngress.isEmpty {
                    tunnel.ingressRules = d.localIngress
                    tunnel.ingressSource = .localConfig
                }
            } else {
                tunnel = NamedCloudflareTunnel(tunnelID: d.tunnelID, name: d.name, createdAt: d.createdAt)
                tunnel.credentialsPath = d.credentialsPath
                tunnel.edgeConnections = d.edgeConnections
                if !d.localIngress.isEmpty {
                    tunnel.ingressRules = d.localIngress
                    tunnel.ingressSource = .localConfig
                }
            }
            // Sticky flag: once we've seen this tunnel referenced by config.yml, remember it
            // even if a later runtime config replaces ingressRules. Otherwise we'd misclassify
            // it as `.managedElsewhere` after it connects and acquires its own edge connections.
            if !d.localIngress.isEmpty {
                tunnel.hasLocalConfigMatch = true
            }
            merged.append(tunnel)
        }

        // Keep tunnels that are currently running locally even if they were de-listed remotely.
        for existing in tunnels where existing.status == .running || existing.status == .starting {
            if !merged.contains(where: { $0.tunnelID == existing.tunnelID }) {
                merged.append(existing)
            }
        }

        tunnels = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Run / Stop

    func run(_ tunnel: NamedCloudflareTunnel, allowManagedElsewhere: Bool = false) {
        guard tunnel.status != .running, tunnel.status != .starting else { return }
        // Warn by default before adding this Mac as another connector for a
        // tunnel that already appears to be managed by a different origin.
        guard allowManagedElsewhere || tunnel.runSafety != .managedElsewhere else {
            tunnel.lastError = "Tunnel is managed elsewhere (active edge connections from other origins)."
            return
        }

        let runID = UUID()
        tunnel.runID = runID
        tunnel.status = .starting
        tunnel.lastError = nil
        tunnel.metricsPort = nil
        tunnel.activeConnectionCount = 0

        Task { [weak self, weak tunnel] in
            guard let self = self, let tunnel = tunnel else { return }
            await self.startNamedTunnel(runID: runID, tunnel: tunnel)
        }
    }

    func stop(_ tunnel: NamedCloudflareTunnel) {
        guard let runID = tunnel.runID else { return }
        tunnel.status = .stopping
        Task { [weak tunnel] in
            await self.cloudflaredService.stopTunnel(id: runID)
            await MainActor.run {
                guard let tunnel = tunnel else { return }
                tunnel.runID = nil
                tunnel.status = .stopped
                tunnel.activeConnectionCount = 0
                tunnel.metricsPort = nil
            }
        }
    }

    func stopAll() async {
        let running = tunnels.filter { $0.runID != nil }
        for tunnel in running {
            tunnel.status = .stopping
        }
        for tunnel in running {
            if let id = tunnel.runID {
                await cloudflaredService.stopTunnel(id: id)
            }
        }
        for tunnel in running {
            tunnel.runID = nil
            tunnel.status = .stopped
            tunnel.activeConnectionCount = 0
            tunnel.metricsPort = nil
        }
    }

    // MARK: - Internal

    private func startNamedTunnel(runID: UUID, tunnel: NamedCloudflareTunnel) async {
        // Log handler: capture every line, parse for state transitions.
        let logHandler: @Sendable (String) -> Void = { [weak self, weak tunnel] line in
            let entry = TunnelLogEntry.parse(line)
            Task { @MainActor [weak self, weak tunnel] in
                guard let tunnel = tunnel else { return }
                tunnel.addLogEntry(entry)
                self?.applyLogLine(line, to: tunnel)
            }
        }
        await cloudflaredService.setLogHandler(for: runID, handler: logHandler)

        let errorHandler: @Sendable (String) -> Void = { [weak tunnel] message in
            Task { @MainActor [weak tunnel] in
                guard let tunnel = tunnel else { return }
                tunnel.lastError = message
                if tunnel.status != .running {
                    tunnel.status = .error
                }
            }
        }
        await cloudflaredService.setErrorHandler(for: runID, handler: errorHandler)

        do {
            let process = try await cloudflaredService.runNamedTunnel(id: runID, tunnelName: tunnel.name)
            tunnel.startedAt = Date()
            // Give it ~3s to register at least one connection; otherwise leave it in .starting and
            // let log parsing flip to .running when "Registered tunnel connection" arrives.
            try? await Task.sleep(for: .seconds(3))

            if !process.isRunning && tunnel.status != .running {
                await cloudflaredService.removeHandlers(for: runID)
                tunnel.status = .error
                if tunnel.lastError == nil {
                    tunnel.lastError = "cloudflared exited unexpectedly"
                }
                tunnel.runID = nil
                return
            }

            await monitorProcess(process, runID: runID, tunnel: tunnel)
        } catch {
            await cloudflaredService.removeHandlers(for: runID)
            tunnel.status = .error
            tunnel.lastError = error.localizedDescription
            tunnel.runID = nil
        }
    }

    private func monitorProcess(_ process: Process, runID: UUID, tunnel: NamedCloudflareTunnel) async {
        while process.isRunning && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }

        guard tunnel.runID == runID else { return }
        await cloudflaredService.removeHandlers(for: runID)

        tunnel.runID = nil
        tunnel.activeConnectionCount = 0
        tunnel.metricsPort = nil

        if tunnel.status == .stopping || process.terminationStatus == 0 {
            tunnel.status = .stopped
        } else {
            tunnel.status = .error
            if tunnel.lastError == nil {
                tunnel.lastError = "cloudflared exited with status \(process.terminationStatus)"
            }
        }
    }

    /// Parse meaningful state out of cloudflared log lines.
    private func applyLogLine(_ line: String, to tunnel: NamedCloudflareTunnel) {
        // First successful registration flips us into Running.
        if line.contains("Registered tunnel connection") {
            tunnel.activeConnectionCount += 1
            if tunnel.status != .running {
                tunnel.status = .running
            }
        } else if line.contains("Unregistered tunnel connection") {
            tunnel.activeConnectionCount = max(0, tunnel.activeConnectionCount - 1)
        }

        // Metrics server port — looks like:
        //   "Starting metrics server on 127.0.0.1:20241/metrics"
        if line.contains("Starting metrics server on"),
           let port = parseMetricsPort(from: line) {
            tunnel.metricsPort = port
        }

        // Runtime ingress config from the dashboard arrives as:
        //   "Updated to new configuration config=\"{...}\" version=N"
        if line.contains("Updated to new configuration"),
           let rules = parseRuntimeIngress(from: line) {
            tunnel.ingressRules = rules
            tunnel.ingressSource = .runtimeLog
        }
    }

    private func parseMetricsPort(from line: String) -> Int? {
        // Match `127.0.0.1:NNNNN`
        let pattern = #"127\.0\.0\.1:(\d+)"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = String(line[range])
        guard let colonIdx = matched.firstIndex(of: ":") else { return nil }
        let portPart = matched[matched.index(after: colonIdx)...]
        // Strip trailing non-digits (e.g. "/metrics").
        let digits = portPart.prefix { $0.isNumber }
        return Int(digits)
    }

    private func parseRuntimeIngress(from line: String) -> [CloudflareTunnelIngressRule]? {
        // The cloudflared log embeds the config JSON inside double quotes with escaped quotes:
        //   config="{\"ingress\":[{\"hostname\":\"foo\",\"service\":\"http://localhost:3000\"}, ...]}"
        // We need to extract the JSON string, unescape it, and parse.
        guard let configRange = line.range(of: "config=\"") else { return nil }
        let afterPrefix = line[configRange.upperBound...]
        // The JSON ends at the last `"` before ` version=` (or end of line).
        let endMarker = afterPrefix.range(of: "\" version=") ?? afterPrefix.range(of: "\"", options: .backwards)
        guard let end = endMarker else { return nil }
        let escapedJSON = String(afterPrefix[..<end.lowerBound])
        let unescaped = escapedJSON
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        guard let data = unescaped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ingress = json["ingress"] as? [[String: Any]] else { return nil }

        return ingress.compactMap { entry -> CloudflareTunnelIngressRule? in
            let hostname = entry["hostname"] as? String
            let path = entry["path"] as? String
            guard let service = entry["service"] as? String else { return nil }
            return CloudflareTunnelIngressRule(hostname: hostname, path: path, service: service)
        }
    }
}
