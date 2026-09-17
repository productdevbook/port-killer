import AppKit
import Observation
import PortKillerKit
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case settings
    case logs
    case info
    case sharing
    case plugins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: "Settings"
        case .logs: "Logs"
        case .info: "Info"
        case .sharing: "Sharing"
        case .plugins: "Plugins"
        }
    }

    var symbol: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .logs: "text.document"
        case .info: "info"
        case .sharing: "cloud"
        case .plugins: "puzzlepiece.extension"
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

    var selection: ItemID?
    var inspectorVisible: Bool {
        didSet { UserDefaults.standard.set(inspectorVisible, forKey: "inspectorVisible") }
    }
    var inspectorTab: InspectorTab {
        didSet { UserDefaults.standard.set(inspectorTab.rawValue, forKey: "inspectorTab") }
    }
    var portScope: PortScope {
        didSet { UserDefaults.standard.set(portScope.rawValue, forKey: "portScope") }
    }
    var searchFocusRequest = 0
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
        inspectorVisible = UserDefaults.standard.object(forKey: "inspectorVisible") as? Bool ?? true
        inspectorTab = UserDefaults.standard.string(forKey: "inspectorTab").flatMap(InspectorTab.init(rawValue:)) ?? .info
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
        selection = id
        show()
    }

    var selectedPorts: [Int] {
        switch selection {
        case .process(let pid): ports.ports.filter { $0.pid == pid }.map(\.port)
        case .inactivePort(let port): [port]
        default: []
        }
    }

    var selectedURL: URL? {
        switch selection {
        case .process(let pid): ports.ports.first { $0.pid == pid }?.localURL
        case .inactivePort, nil: nil
        case .forward(let id): forwards.sessions.first { $0.id == id }?.configuration.localURL
        case .quickTunnel(let id): tunnels.quickTunnels.first { $0.id == id }?.url
        case .namedTunnel(let id): tunnels.namedTunnels.first { $0.id == id }?.publicURLs.first.flatMap(URL.init(string:))
        case .pluginItem(let plugin, let item): plugins.items[plugin]?.first { $0.id == item }?.url
        }
    }

    func addForward(_ configuration: PortForwardConfiguration, start: Bool = false) {
        let session = forwards.add(configuration, start: start)
        selection = .forward(session.id)
        inspectorTab = .settings
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
