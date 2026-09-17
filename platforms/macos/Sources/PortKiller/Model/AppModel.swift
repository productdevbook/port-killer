import AppKit
import Observation
import PortKillerKit
import SwiftUI

@Observable
final class AppModel {
    let preferences: Preferences
    let notifier: Notifier
    let ports: PortStore
    let forwards: PortForwardStore
    let tunnels: TunnelStore
    let sponsors: SponsorStore
    let installer: ToolInstaller
    let loginItem = LoginItem()
    let updater = Updater()
    let explainer = ProcessExplainer()

    var sidebar: SidebarItem {
        didSet { UserDefaults.standard.set(sidebar.storageValue, forKey: "sidebarSelection") }
    }
    var inspectorVisible = true
    var showingOnboarding: Bool
    @ObservationIgnored var openWindow: OpenWindowAction?

    init() {
        let preferences = Preferences()
        let notifier = Notifier()
        self.preferences = preferences
        self.notifier = notifier
        ports = PortStore(preferences: preferences, notifier: notifier)
        forwards = PortForwardStore(preferences: preferences, notifier: notifier)
        tunnels = TunnelStore(preferences: preferences, notifier: notifier)
        sponsors = SponsorStore(preferences: preferences)
        installer = ToolInstaller(preferences: preferences)
        showingOnboarding = !preferences.hasCompletedOnboarding
        sidebar = UserDefaults.standard.string(forKey: "sidebarSelection").flatMap(SidebarItem.init(storageValue:)) ?? .allPorts
    }

    func start() {
        notifier.setUp()
        updater.start()
        ports.start()
        tunnels.cleanUpOrphans()
        forwards.startAutomatically()
        HotKeyCenter.shared.action = { [weak self] in self?.toggleMainWindow() }
        HotKeyCenter.shared.register(preferences.toggleWindowShortcut)
        Task(name: "Sponsors") { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            await sponsors.refreshIfStale()
            if sponsors.isDue, preferences.hasCompletedOnboarding {
                show(.sponsors)
                sponsors.markShown()
            }
        }
    }

    func shutDown() async {
        await forwards.stopAllAndWait()
        await tunnels.stopEverythingAndWait()
    }

    func show(_ item: SidebarItem? = nil) {
        if let item { sidebar = item }
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?(id: "main")
        }
        NSApp.activate()
    }

    func toggleMainWindow() {
        if let window = mainWindow, window.isVisible, window.isKeyWindow, NSApp.isActive {
            window.close()
        } else {
            show()
        }
    }

    var selectedListeners: [ListeningPort] {
        listeners(ids: ports.selection)
    }

    func listeners(ids: Set<PortRow.ID>) -> [ListeningPort] {
        ports.listeners(ids: ids, in: sidebar)
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        showingOnboarding = false
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }
}
