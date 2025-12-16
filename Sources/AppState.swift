import Foundation
import SwiftUI
@preconcurrency import UserNotifications
import Defaults
import KeyboardShortcuts
import Sparkle

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let favorites = Key<Set<Int>>("favorites", default: [])
    static let watchedPorts = Key<[WatchedPort]>("watchedPorts", default: [])
    static let useTreeView = Key<Bool>("useTreeView", default: false)
    static let refreshInterval = Key<Int>("refreshInterval", default: 5)
}

// MARK: - Keyboard Shortcuts

extension KeyboardShortcuts.Name {
    static let toggleMainWindow = Self("toggleMainWindow", default: .init(.p, modifiers: [.command, .shift]))
}

// MARK: - App State

@Observable
@MainActor
final class AppState: NSObject {
    // MARK: - Port State
    var ports: [PortInfo] = []
    var isScanning = false

    // MARK: - Filter State (for main window)
    var filter = PortFilter()
    var selectedSidebarItem: SidebarItem = .allPorts
    var selectedPortID: UUID? = nil

    var selectedPort: PortInfo? {
        guard let id = selectedPortID else { return nil }
        return ports.first { $0.id == id }
    }

    var filteredPorts: [PortInfo] {
        var result = ports

        // Apply sidebar selection
        switch selectedSidebarItem {
        case .allPorts:
            break
        case .favorites:
            // Show active favorites + inactive favorites
            let activeFavoritePorts = Set(result.filter { favorites.contains($0.port) }.map { $0.port })
            result = result.filter { favorites.contains($0.port) }
            // Add inactive favorites (not currently running)
            for favPort in favorites where !activeFavoritePorts.contains(favPort) {
                result.append(PortInfo.inactive(port: favPort))
            }
        case .watched:
            let watchedPortNumbers = Set(watchedPorts.map { $0.port })
            // Show active watched + inactive watched
            let activeWatchedPorts = Set(result.filter { watchedPortNumbers.contains($0.port) }.map { $0.port })
            result = result.filter { watchedPortNumbers.contains($0.port) }
            // Add inactive watched (not currently running)
            for watchedPort in watchedPortNumbers where !activeWatchedPorts.contains(watchedPort) {
                result.append(PortInfo.inactive(port: watchedPort))
            }
        case .processType(let type):
            result = result.filter { $0.processType == type }
        case .settings:
            break
        }

        // Apply additional filters
        result = result.filter { filter.matches($0, favorites: favorites, watched: watchedPorts) }

        return result
    }

    // MARK: - Favorites (cached for reactivity)
    private var _favorites: Set<Int> = Defaults[.favorites] {
        didSet { Defaults[.favorites] = _favorites }
    }
    var favorites: Set<Int> {
        get { _favorites }
        set { _favorites = newValue }
    }

    // MARK: - Watch (cached for reactivity)
    private var _watchedPorts: [WatchedPort] = Defaults[.watchedPorts] {
        didSet { Defaults[.watchedPorts] = _watchedPorts }
    }
    var watchedPorts: [WatchedPort] {
        get { _watchedPorts }
        set { _watchedPorts = newValue }
    }

    // MARK: - Update Manager
    let updateManager = UpdateManager()

    // MARK: - Private
    private let scanner = PortScanner()
    private var refreshTask: Task<Void, Never>?
    private var previousPortStates: [Int: Bool] = [:]
    @ObservationIgnored
    private lazy var notificationCenter: UNUserNotificationCenter? = {
        // UNUserNotificationCenter only works in .app bundle
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        return UNUserNotificationCenter.current()
    }()

    // MARK: - Init
    override init() {
        super.init()
        setupKeyboardShortcuts()
        setupNotifications()
        startAutoRefresh()
    }

    // MARK: - Port Operations
    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let scanned = await scanner.scanPorts()
        updatePorts(scanned)
        checkWatchedPorts()
    }

    private func updatePorts(_ newPorts: [PortInfo]) {
        let newSet = Set(newPorts.map { "\($0.port)-\($0.pid)" })
        let oldSet = Set(ports.map { "\($0.port)-\($0.pid)" })
        guard newSet != oldSet else { return }

        ports = newPorts.sorted { a, b in
            let aFav = favorites.contains(a.port)
            let bFav = favorites.contains(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }
    }

    func killPort(_ port: PortInfo) async {
        if await scanner.killProcessGracefully(pid: port.pid) {
            ports.removeAll { $0.id == port.id }
            await refresh()
        }
    }

    func killAll() async {
        for port in ports {
            _ = await scanner.killProcessGracefully(pid: port.pid)
        }
        ports.removeAll()
        await refresh()
    }

    // MARK: - Auto Refresh
    private func startAutoRefresh() {
        refreshTask = Task { @MainActor in
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Defaults[.refreshInterval]))
                if !Task.isCancelled { await self.refresh() }
            }
        }
    }

    // MARK: - Favorites
    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) { favorites.remove(port) }
        else { favorites.insert(port) }
    }

    func isFavorite(_ port: Int) -> Bool { favorites.contains(port) }

    // MARK: - Watch
    func toggleWatch(_ port: Int) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            previousPortStates.removeValue(forKey: port)
            watchedPorts.remove(at: idx)
        } else {
            watchedPorts.append(WatchedPort(port: port))
        }
    }

    func isWatching(_ port: Int) -> Bool { watchedPorts.contains { $0.port == port } }

    func updateWatch(_ port: Int, onStart: Bool, onStop: Bool) {
        if let idx = watchedPorts.firstIndex(where: { $0.port == port }) {
            watchedPorts[idx].notifyOnStart = onStart
            watchedPorts[idx].notifyOnStop = onStop
        }
    }

    func removeWatch(_ id: UUID) {
        if let w = watchedPorts.first(where: { $0.id == id }) {
            previousPortStates.removeValue(forKey: w.port)
        }
        watchedPorts.removeAll { $0.id == id }
    }

    private func checkWatchedPorts() {
        let activePorts = Set(ports.map { $0.port })
        for w in watchedPorts {
            let isActive = activePorts.contains(w.port)
            if let wasActive = previousPortStates[w.port] {
                if wasActive && !isActive && w.notifyOnStop {
                    notify("Port \(String(w.port)) Available", "Port is now free.")
                } else if !wasActive && isActive && w.notifyOnStart {
                    let name = ports.first { $0.port == w.port }?.processName ?? "Unknown"
                    notify("Port \(String(w.port)) In Use", "Used by \(name).")
                }
            }
            previousPortStates[w.port] = isActive
        }
    }

    // MARK: - Keyboard Shortcuts
    private func setupKeyboardShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleMainWindow) { [weak self] in
            Task { @MainActor in
                self?.toggleMainWindow()
            }
        }
    }

    private func toggleMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "PortKiller" || $0.identifier?.rawValue == "main" }) {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Notifications
    private func setupNotifications() {
        guard let center = notificationCenter else { return }
        center.delegate = self
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard let center = notificationCenter else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppState: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
