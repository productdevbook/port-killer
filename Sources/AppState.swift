import Foundation
import SwiftUI
import ServiceManagement
@preconcurrency import UserNotifications
import HotKey
import Carbon

@Observable
@MainActor
final class AppState: NSObject {
    // MARK: - Port State
    var ports: [PortInfo] = []
    var isScanning = false

    // MARK: - Favorites (persisted as Set<Int>)
    var favorites: Set<Int> = [] {
        didSet { saveFavorites() }
    }

    // MARK: - Watch (persisted)
    var watchedPorts: [WatchedPort] = [] {
        didSet { saveWatched() }
    }

    // MARK: - Settings
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {}
        }
    }

    // TODO: Hotkey feature disabled for now - will be improved in next version
    var hotkeyEnabled: Bool = false

    // MARK: - Private
    private let scanner = PortScanner()
    private var refreshTask: Task<Void, Never>?
    private var previousPortStates: [Int: Bool] = [:]
    // private var hotkey: HotKey?
    private var notificationCenter: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    // MARK: - Init
    override init() {
        super.init()
        loadFavorites()
        loadWatched()
        // setupHotkey() // Disabled for now
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
        refreshTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { await refresh() }
            }
        }
    }

    // MARK: - Favorites
    func toggleFavorite(_ port: Int) {
        if favorites.contains(port) { favorites.remove(port) }
        else { favorites.insert(port) }
    }

    func isFavorite(_ port: Int) -> Bool { favorites.contains(port) }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favorites), forKey: "favoritesV2")
    }

    private func loadFavorites() {
        favorites = Set(UserDefaults.standard.array(forKey: "favoritesV2") as? [Int] ?? [])
    }

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

    private func saveWatched() {
        if let data = try? JSONEncoder().encode(watchedPorts) {
            UserDefaults.standard.set(data, forKey: "watchedV2")
        }
    }

    private func loadWatched() {
        if let data = UserDefaults.standard.data(forKey: "watchedV2"),
           let decoded = try? JSONDecoder().decode([WatchedPort].self, from: data) {
            watchedPorts = decoded
        }
    }

    private func checkWatchedPorts() {
        let activePorts = Set(ports.map { $0.port })
        for w in watchedPorts {
            let isActive = activePorts.contains(w.port)
            if let wasActive = previousPortStates[w.port] {
                if wasActive && !isActive && w.notifyOnStop {
                    notify("Port \(w.port) Available", "Port is now free.")
                } else if !wasActive && isActive && w.notifyOnStart {
                    let name = ports.first { $0.port == w.port }?.processName ?? "Unknown"
                    notify("Port \(w.port) In Use", "Used by \(name).")
                }
            }
            previousPortStates[w.port] = isActive
        }
    }

    // MARK: - Notifications
    private func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        notificationCenter.delegate = self
        let center = notificationCenter
        center.getNotificationSettings { s in
            if s.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Hotkey (Disabled for now)
    /*
    private func setupHotkey() {
        hotkey = HotKey(key: .p, modifiers: [.command, .shift])
        hotkey?.keyDownHandler = { [weak self] in
            Task { @MainActor in self?.toggleMenuBar() }
        }
    }

    private func toggleMenuBar() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("NSStatusBarWindow") {
                if let button = window.contentView?.subviews.compactMap({ $0 as? NSStatusBarButton }).first {
                    button.performClick(nil)
                    return
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    */
}

// MARK: - UNUserNotificationCenterDelegate
extension AppState: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
