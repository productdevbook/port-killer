import Foundation
import Observation
import PortKillerKit

@Observable
final class Preferences {
    enum Key {
        static let favorites = "favorites"
        static let watchedPorts = "watchedPorts"
        static let portLabels = "portLabels"
        static let portNotes = "portNotes"
        static let categoryOverrides = "processTypeOverrides"
        static let notifyCategories = "notifyProcessTypes"
        static let autoKillRules = "autoKillRules"
        static let useTreeView = "useTreeView"
        static let hideSystemProcesses = "hideSystemProcesses"
        static let skipKillConfirmation = "skipKillConfirmation"
        static let refreshInterval = "refreshInterval"
        static let quickTunnelProtocol = "cloudflaredProtocol"
        static let customNamespaces = "customNamespaces"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let portForwards = "portForwardConnections"
        static let portForwardAutoStart = "portForwardAutoStart"
        static let portForwardNotifications = "portForwardShowNotifications"
        static let kubectlPath = "customKubectlPath"
        static let socatPath = "customSocatPath"
        static let cloudflaredPath = "customCloudflaredPath"
        static let sponsorInterval = "sponsorDisplayInterval"
        static let sponsorLastShown = "lastSponsorWindowShown"
        static let sponsorCache = "sponsorCache"
        static let toggleWindowShortcut = "KeyboardShortcuts_toggleMainWindow"
        static let explainProcesses = "explainProcessesWithAppleIntelligence"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var favorites: Set<Int> { didSet { defaults.set(favorites.sorted(), forKey: Key.favorites) } }
    var watchedPorts: [WatchedPort] { didSet { defaults.setEncodedArray(watchedPorts, forKey: Key.watchedPorts) } }
    var portLabels: [String: String] { didSet { defaults.set(portLabels, forKey: Key.portLabels) } }
    var portNotes: [String: String] { didSet { defaults.set(portNotes, forKey: Key.portNotes) } }
    var categoryOverrides: [String: String] { didSet { defaults.set(categoryOverrides, forKey: Key.categoryOverrides) } }
    var notifyCategories: Set<String> { didSet { defaults.set(notifyCategories.sorted(), forKey: Key.notifyCategories) } }
    var autoKillRules: [AutoKillRule] { didSet { defaults.setEncodedArray(autoKillRules, forKey: Key.autoKillRules) } }
    var useTreeView: Bool { didSet { defaults.set(useTreeView, forKey: Key.useTreeView) } }
    var hideSystemProcesses: Bool { didSet { defaults.set(hideSystemProcesses, forKey: Key.hideSystemProcesses) } }
    var skipKillConfirmation: Bool { didSet { defaults.set(skipKillConfirmation, forKey: Key.skipKillConfirmation) } }
    var refreshInterval: Int { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    var quickTunnelProtocol: QuickTunnelProtocol { didSet { defaults.set(quickTunnelProtocol.rawValue, forKey: Key.quickTunnelProtocol) } }
    var customNamespaces: [String] { didSet { defaults.set(customNamespaces, forKey: Key.customNamespaces) } }
    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    var portForwards: [PortForwardConfiguration] { didSet { defaults.setEncodedArray(portForwards, forKey: Key.portForwards) } }
    var portForwardAutoStart: Bool { didSet { defaults.set(portForwardAutoStart, forKey: Key.portForwardAutoStart) } }
    var portForwardNotifications: Bool { didSet { defaults.set(portForwardNotifications, forKey: Key.portForwardNotifications) } }
    var kubectlPath: String { didSet { store(path: kubectlPath, forKey: Key.kubectlPath) } }
    var socatPath: String { didSet { store(path: socatPath, forKey: Key.socatPath) } }
    var cloudflaredPath: String { didSet { store(path: cloudflaredPath, forKey: Key.cloudflaredPath) } }
    var sponsorInterval: SponsorDisplayInterval { didSet { defaults.set(sponsorInterval.rawValue, forKey: Key.sponsorInterval) } }
    var sponsorLastShown: Date? { didSet { defaults.set(sponsorLastShown, forKey: Key.sponsorLastShown) } }
    var sponsorCache: SponsorCache? { didSet { defaults.setEncodedValue(sponsorCache, forKey: Key.sponsorCache) } }
    var toggleWindowShortcut: KeyShortcut? {
        didSet {
            if let toggleWindowShortcut {
                defaults.setEncodedValue(toggleWindowShortcut, forKey: Key.toggleWindowShortcut)
            } else {
                defaults.set("false", forKey: Key.toggleWindowShortcut)
            }
        }
    }
    var explainProcesses: Bool { didSet { defaults.set(explainProcesses, forKey: Key.explainProcesses) } }
    private(set) var toolsRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = defaults.integerSet(forKey: Key.favorites)
        watchedPorts = defaults.decodedArray(of: WatchedPort.self, forKey: Key.watchedPorts)
        portLabels = defaults.stringDictionary(forKey: Key.portLabels)
        portNotes = defaults.stringDictionary(forKey: Key.portNotes)
        categoryOverrides = defaults.stringDictionary(forKey: Key.categoryOverrides)
        notifyCategories = Set(defaults.stringArray(forKey: Key.notifyCategories) ?? [])
        autoKillRules = defaults.decodedArray(of: AutoKillRule.self, forKey: Key.autoKillRules)
        useTreeView = defaults.bool(forKey: Key.useTreeView)
        hideSystemProcesses = defaults.bool(forKey: Key.hideSystemProcesses)
        skipKillConfirmation = defaults.bool(forKey: Key.skipKillConfirmation)
        refreshInterval = defaults.object(forKey: Key.refreshInterval) as? Int ?? 3
        quickTunnelProtocol = Self.decodedEnum(defaults, Key.quickTunnelProtocol) ?? .http2
        customNamespaces = defaults.stringArray(forKey: Key.customNamespaces) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        portForwards = defaults.decodedArray(of: PortForwardConfiguration.self, forKey: Key.portForwards)
        portForwardAutoStart = defaults.bool(forKey: Key.portForwardAutoStart)
        portForwardNotifications = defaults.object(forKey: Key.portForwardNotifications) as? Bool ?? true
        kubectlPath = defaults.string(forKey: Key.kubectlPath) ?? ""
        socatPath = defaults.string(forKey: Key.socatPath) ?? ""
        cloudflaredPath = defaults.string(forKey: Key.cloudflaredPath) ?? ""
        sponsorInterval = Self.decodedEnum(defaults, Key.sponsorInterval) ?? .bimonthly
        sponsorLastShown = defaults.object(forKey: Key.sponsorLastShown) as? Date
        sponsorCache = defaults.decodedValue(of: SponsorCache.self, forKey: Key.sponsorCache)
        toggleWindowShortcut = defaults.decodedValue(of: KeyShortcut.self, forKey: Key.toggleWindowShortcut)
        explainProcesses = defaults.object(forKey: Key.explainProcesses) as? Bool ?? true
    }

    private func store(path: String, forKey key: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }

    private static func decodedEnum<Value: RawRepresentable & Decodable>(_ defaults: UserDefaults, _ key: String) -> Value? where Value.RawValue == String {
        defaults.string(forKey: key).flatMap { Value(rawValue: $0) } ?? defaults.decodedValue(of: Value.self, forKey: key)
    }

    func label(for port: Int) -> String? {
        portLabels[String(port)].flatMap { $0.isEmpty ? nil : $0 }
    }

    func setLabel(_ label: String, for port: Int) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        portLabels[String(port)] = trimmed.isEmpty ? nil : trimmed
    }

    func note(for port: Int) -> String? {
        portNotes[String(port)].flatMap { $0.isEmpty ? nil : $0 }
    }

    func setNote(_ note: String, for port: Int) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        portNotes[String(port)] = trimmed.isEmpty ? nil : trimmed
    }

    func categoryOverride(for processName: String) -> ProcessCategory? {
        categoryOverrides[processName].flatMap(ProcessCategory.init(rawValue:))
    }

    func setCategoryOverride(_ category: ProcessCategory?, for processName: String) {
        categoryOverrides[processName] = category?.rawValue
    }

    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) {
            favorites.remove(port)
        } else {
            favorites.insert(port)
        }
    }

    func isWatching(_ port: Int) -> Bool {
        watchedPorts.contains { $0.port == port }
    }

    func toggleWatch(_ port: Int) {
        if let index = watchedPorts.firstIndex(where: { $0.port == port }) {
            watchedPorts.remove(at: index)
        } else {
            watchedPorts.append(WatchedPort(port: port))
        }
    }

    func path(for tool: CommandLineTool) -> String {
        switch tool {
        case .kubectl: kubectlPath
        case .socat: socatPath
        case .cloudflared: cloudflaredPath
        default: ""
        }
    }

    func setPath(_ path: String, for tool: CommandLineTool) {
        switch tool {
        case .kubectl: kubectlPath = path
        case .socat: socatPath = path
        case .cloudflared: cloudflaredPath = path
        default: break
        }
        toolsChanged()
    }

    func locate(_ tool: CommandLineTool) -> URL? {
        _ = toolsRevision
        return tool.locate(customPath: path(for: tool))
    }

    func toolsChanged() {
        toolsRevision += 1
    }
}
