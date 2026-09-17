import AppKit
import Observation
import PortKillerKit
import SwiftUI

enum AppTab: Hashable {
    case ports
    case forwards
    case tunnels
    case plugin(Plugin.ID)

    init(storageValue: String) {
        switch storageValue {
        case "forwards": self = .forwards
        case "tunnels": self = .tunnels
        case let value where value.hasPrefix("plugin:"): self = .plugin(String(value.dropFirst("plugin:".count)))
        default: self = .ports
        }
    }

    var storageValue: String {
        switch self {
        case .ports: "ports"
        case .forwards: "forwards"
        case .tunnels: "tunnels"
        case .plugin(let id): "plugin:\(id)"
        }
    }
}

@Observable
final class AppModel {
    let preferences: Preferences
    let notifier: Notifier
    let ports: PortStore
    let forwards: PortForwardStore
    let tunnels: TunnelStore
    let sponsors: SponsorStore
    let installer: ToolInstaller
    let plugins: PluginStore
    let loginItem = LoginItem()
    let updater = Updater()
    let explainer = ProcessExplainer()

    var tab: AppTab {
        didSet { UserDefaults.standard.set(tab.storageValue, forKey: "selectedTab") }
    }
    var inspectorVisible: Bool {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: "inspectorVisible") }
    }
    var portScope: PortScope {
        didSet { UserDefaults.standard.set(portScope.rawValue, forKey: "portScope") }
    }
    var portSelection: Set<ItemID> = []
    var forwardSelection: Set<PortForwardSession.ID> = []
    var tunnelSelection: Set<ItemID> = []
    var pluginSelection: Set<PluginItem.ID> = []
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
        plugins = PluginStore(notifier: notifier)
        showingOnboarding = !preferences.hasCompletedOnboarding
        portScope = UserDefaults.standard.string(forKey: "portScope").flatMap(PortScope.init(rawValue:)) ?? .all
        inspectorVisible = UserDefaults.standard.bool(forKey: "inspectorVisible")
        tab = AppTab(storageValue: UserDefaults.standard.string(forKey: "selectedTab") ?? "")
        if case .plugin(let id) = tab, !plugins.tabPlugins.contains(where: { $0.id == id }) {
            tab = .ports
        }
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
                showSponsors()
                sponsors.markShown()
            }
        }
    }

    func shutDown() async {
        await forwards.stopAllAndWait()
        await tunnels.stopEverythingAndWait()
    }

    func show() {
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

    func showSponsors() {
        openWindow?(id: "sponsors")
        NSApp.activate()
    }

    func reveal(_ id: ItemID) {
        switch id {
        case .listener, .process, .inactivePort:
            tab = .ports
            portSelection = [id]
        case .quickTunnel, .namedTunnel:
            tab = .tunnels
            tunnelSelection = [id]
        }
        inspectorVisible = true
        show()
    }

    var selectedListeners: [ListeningPort] {
        listeners(ids: portSelection)
    }

    func listeners(ids: Set<ItemID>) -> [ListeningPort] {
        ports.listeners(ids: ids, in: portScope)
    }

    func addForward(_ configuration: PortForwardConfiguration, start: Bool = false) {
        let session = forwards.add(configuration, start: start)
        tab = .forwards
        forwardSelection = [session.id]
        inspectorVisible = true
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        showingOnboarding = false
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
    }
}
