import AppKit
import AsyncAlgorithms
import DequeModule
import Observation
import PortKillerKit

struct PortExposure: Hashable {
    var hostname: String
    var publicURL: String
    var tunnelName: String
    var tunnelID: String
}

enum TunnelSelection: Hashable {
    case quick(QuickTunnel.ID)
    case named(NamedTunnel.ID)
}

@Observable
final class QuickTunnel: Identifiable {
    enum Status: Equatable {
        case starting
        case active
        case stopping
        case failed
    }

    let id = UUID()
    let port: Int
    fileprivate(set) var status: Status = .starting
    fileprivate(set) var url: String?
    fileprivate(set) var lastError: String?
    fileprivate(set) var startedAt: Date?
    fileprivate(set) var logs: Deque<TunnelLogEntry> = []
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(port: Int) {
        self.port = port
    }

    fileprivate func append(_ line: String) {
        logs.append(TunnelLogEntry(message: line))
        if logs.count > 500 { logs.removeFirst() }
    }

    func clearLogs() {
        logs.removeAll()
    }
}

@Observable
final class NamedTunnel: Identifiable {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case failed
    }

    enum IngressSource {
        case none
        case localConfiguration
        case dashboard
    }

    let id: String
    fileprivate(set) var name: String
    fileprivate(set) var createdAt: Date?
    fileprivate(set) var credentialsPath: String?
    fileprivate(set) var ingressRules: [TunnelIngressRule] = []
    fileprivate(set) var ingressSource: IngressSource = .none
    fileprivate(set) var hasLocalConfiguration = false
    fileprivate(set) var edgeConnections: [TunnelEdgeConnection] = []
    fileprivate(set) var status: Status = .stopped
    fileprivate(set) var startedAt: Date?
    fileprivate(set) var lastError: String?
    fileprivate(set) var metricsPort: Int?
    fileprivate(set) var activeConnections = 0
    fileprivate(set) var logs: Deque<TunnelLogEntry> = []
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(_ discovered: DiscoveredTunnel) {
        id = discovered.id
        name = discovered.name
        apply(discovered)
    }

    var isRunningHere: Bool {
        status == .running || status == .starting
    }

    var runSafety: TunnelRunSafety {
        TunnelRunSafety.evaluate(isRunningHere: isRunningHere, hasLocalConfig: hasLocalConfiguration, edgeConnectionCount: edgeConnections.count)
    }

    var publicURLs: [String] {
        ingressRules.compactMap(\.publicURL)
    }

    fileprivate func apply(_ discovered: DiscoveredTunnel) {
        name = discovered.name
        createdAt = discovered.createdAt
        credentialsPath = discovered.credentialsPath
        if !discovered.localIngress.isEmpty { hasLocalConfiguration = true }
        guard !isRunningHere else { return }
        edgeConnections = discovered.edgeConnections
        if ingressSource != .dashboard, !discovered.localIngress.isEmpty {
            ingressRules = discovered.localIngress
            ingressSource = .localConfiguration
        }
    }

    fileprivate func append(_ line: String) {
        logs.append(TunnelLogEntry(message: line))
        if logs.count > 500 { logs.removeFirst() }
    }

    func clearLogs() {
        logs.removeAll()
    }
}

@Observable
final class TunnelStore {
    let preferences: Preferences
    let notifier: Notifier

    private(set) var quickTunnels: [QuickTunnel] = []
    private(set) var namedTunnels: [NamedTunnel] = []
    private(set) var isDiscovering = false
    private(set) var hasDiscovered = false
    private(set) var isLoggedIn = Cloudflared.isLoggedIn
    var selection: TunnelSelection?

    @ObservationIgnored private var discoveryLoop: Task<Void, Never>?

    init(preferences: Preferences, notifier: Notifier) {
        self.preferences = preferences
        self.notifier = notifier
    }

    var cloudflared: Cloudflared? {
        preferences.locate(.cloudflared).map(Cloudflared.init(executable:))
    }

    var isInstalled: Bool { cloudflared != nil }

    var activeQuickCount: Int { quickTunnels.count { $0.status == .active } }
    var runningNamedCount: Int { namedTunnels.count { $0.status == .running } }

    var exposuresByPort: [Int: [PortExposure]] {
        var result: [Int: [PortExposure]] = [:]
        for tunnel in namedTunnels where tunnel.status == .running {
            for rule in tunnel.ingressRules {
                guard let port = rule.localPort, let hostname = rule.hostname, let url = rule.publicURL else { continue }
                result[port, default: []].append(PortExposure(hostname: hostname, publicURL: url, tunnelName: tunnel.name, tunnelID: tunnel.id))
            }
        }
        return result
    }

    func quickTunnel(for port: Int) -> QuickTunnel? {
        quickTunnels.first { $0.port == port && $0.status != .failed } ?? quickTunnels.first { $0.port == port }
    }

    func recheckInstallation() {
        preferences.toolsChanged()
        isLoggedIn = Cloudflared.isLoggedIn
    }

    func cleanUpOrphans() {
        Task(name: "Clean up orphaned tunnels") {
            _ = try? await CommandRunner.run(URL(filePath: "/usr/bin/pkill"), ["-9", "-f", Cloudflared.orphanedQuickTunnelPattern])
        }
    }

    func startQuickTunnel(port: Int) {
        if let existing = quickTunnel(for: port) {
            if existing.status == .failed {
                quickTunnels.removeAll { $0.id == existing.id }
            } else {
                if let url = existing.url { Pasteboard.copy(url) }
                return
            }
        }
        guard let cloudflared else { return }
        let tunnel = QuickTunnel(port: port)
        quickTunnels.append(tunnel)
        let arguments = Cloudflared.quickTunnelArguments(port: port, protocol: preferences.quickTunnelProtocol)
        tunnel.task = Task(name: "Quick tunnel \(port)") { [weak self, weak tunnel] in
            do {
                let status = try await CommandRunner.stream(cloudflared.executable, arguments, environment: ["PATH": CommandLineTool.searchPath]) { @MainActor [weak self, weak tunnel] line in
                    guard let tunnel else { return }
                    self?.receive(line, for: tunnel)
                }
                guard let tunnel else { return }
                if tunnel.status == .stopping {
                    self?.quickTunnels.removeAll { $0.id == tunnel.id }
                } else {
                    tunnel.status = .failed
                    tunnel.lastError = tunnel.lastError ?? "cloudflared exited with status \(status)"
                }
            } catch {
                if let tunnel, tunnel.status == .stopping {
                    self?.quickTunnels.removeAll { $0.id == tunnel.id }
                } else {
                    tunnel?.status = .failed
                    tunnel?.lastError = error.localizedDescription
                }
            }
            tunnel?.task = nil
        }
    }

    func stopQuickTunnel(_ tunnel: QuickTunnel) {
        guard let task = tunnel.task else {
            quickTunnels.removeAll { $0.id == tunnel.id }
            return
        }
        tunnel.status = .stopping
        task.cancel()
    }

    func stopQuickTunnel(port: Int) {
        if let tunnel = quickTunnel(for: port) { stopQuickTunnel(tunnel) }
    }

    func stopAllQuickTunnels() {
        quickTunnels.forEach(stopQuickTunnel)
    }

    private func receive(_ line: String, for tunnel: QuickTunnel) {
        tunnel.append(line)
        if tunnel.url == nil, let url = CloudflaredOutput.quickTunnelURL(in: line) {
            tunnel.url = url
            tunnel.status = .active
            tunnel.startedAt = Date()
            tunnel.lastError = nil
            Pasteboard.copy(url)
            notifier.post(title: "Tunnel Active", body: "Port \(tunnel.port) is available at \(url.replacingOccurrences(of: "https://", with: "")). The URL is on your clipboard.")
        } else if tunnel.status != .active, TunnelLogLevel.classify(line) == .error {
            tunnel.lastError = line
        }
    }

    func startDiscovery() {
        discover()
        guard discoveryLoop == nil else { return }
        discoveryLoop = Task(name: "Tunnel discovery") { [weak self] in
            for await _ in AsyncTimerSequence(interval: .seconds(30), clock: .continuous) {
                await self?.discoverNow()
            }
        }
    }

    func stopDiscovery() {
        discoveryLoop?.cancel()
        discoveryLoop = nil
    }

    func discover() {
        Task(name: "Discover tunnels") { await discoverNow() }
    }

    func discoverIfNeeded() {
        if !hasDiscovered { discover() }
    }

    private func discoverNow() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer {
            isDiscovering = false
            hasDiscovered = true
        }
        isLoggedIn = Cloudflared.isLoggedIn
        let executable = preferences.locate(.cloudflared)
        let discovered = await TunnelDiscovery.discover(executable: executable)
        var existing = Dictionary(uniqueKeysWithValues: namedTunnels.map { ($0.id, $0) })
        var merged: [NamedTunnel] = []
        for item in discovered {
            if let tunnel = existing.removeValue(forKey: item.id) {
                tunnel.apply(item)
                merged.append(tunnel)
            } else {
                merged.append(NamedTunnel(item))
            }
        }
        merged += existing.values.filter(\.isRunningHere)
        namedTunnels = merged.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func run(_ tunnel: NamedTunnel, allowManagedElsewhere: Bool = false) {
        guard !tunnel.isRunningHere, let cloudflared else { return }
        guard allowManagedElsewhere || tunnel.runSafety != .managedElsewhere else {
            tunnel.lastError = "This tunnel is managed by another connector."
            return
        }
        tunnel.status = .starting
        tunnel.lastError = nil
        tunnel.metricsPort = nil
        tunnel.activeConnections = 0
        tunnel.startedAt = Date()
        let arguments = Cloudflared.namedTunnelArguments(name: tunnel.name)
        tunnel.task = Task(name: "Named tunnel \(tunnel.name)") { [weak tunnel] in
            do {
                let status = try await CommandRunner.stream(cloudflared.executable, arguments, environment: ["PATH": CommandLineTool.searchPath]) { @MainActor [weak tunnel] line in
                    tunnel?.receive(line)
                }
                guard let tunnel else { return }
                if tunnel.status == .stopping || status == 0 {
                    tunnel.status = .stopped
                } else {
                    tunnel.status = .failed
                    tunnel.lastError = tunnel.lastError ?? "cloudflared exited with status \(status)"
                }
            } catch {
                if tunnel?.status == .stopping {
                    tunnel?.status = .stopped
                } else {
                    tunnel?.status = .failed
                    tunnel?.lastError = error.localizedDescription
                }
            }
            tunnel?.activeConnections = 0
            tunnel?.metricsPort = nil
            tunnel?.task = nil
        }
    }

    func stop(_ tunnel: NamedTunnel) {
        guard let task = tunnel.task else { return }
        tunnel.status = .stopping
        task.cancel()
    }

    func stopAllNamedTunnels() {
        namedTunnels.forEach(stop)
    }

    func stopEverythingAndWait() async {
        let tasks = quickTunnels.compactMap(\.task) + namedTunnels.compactMap(\.task)
        stopAllQuickTunnels()
        stopAllNamedTunnels()
        for task in tasks {
            await task.value
        }
    }
}

private extension NamedTunnel {
    func receive(_ line: String) {
        append(line)
        for event in CloudflaredOutput.namedTunnelEvents(in: line) {
            switch event {
            case .connectionRegistered:
                activeConnections += 1
                status = .running
            case .connectionUnregistered:
                activeConnections = max(0, activeConnections - 1)
            case .metricsPort(let port):
                metricsPort = port
            case .ingress(let rules):
                ingressRules = rules
                ingressSource = .dashboard
            }
        }
        if status != .running, TunnelLogLevel.classify(line) == .error {
            lastError = line
        }
    }
}
