import AppKit
import Observation
import PortKillerKit

@Observable
final class PluginStore {
    let notifier: Notifier

    private(set) var plugins: [Plugin] = []
    private(set) var failures: [PluginLoadFailure] = []
    private(set) var enabledIDs: Set<Plugin.ID>
    private(set) var items: [Plugin.ID: [PluginItem]] = [:]
    private(set) var itemErrors: [Plugin.ID: String] = [:]
    private(set) var loading: Set<Plugin.ID> = []
    private(set) var performing: Set<String> = []
    var error: PresentedError?

    init(notifier: Notifier) {
        self.notifier = notifier
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? [])
        reload()
    }

    var enabledPlugins: [Plugin] {
        plugins.filter { enabledIDs.contains($0.id) }
    }

    var tabPlugins: [Plugin] {
        enabledPlugins.filter { $0.manifest.items != nil }
    }

    func reload() {
        let result = PluginHost.discover()
        plugins = result.plugins
        failures = result.failures
        let ids = Set(plugins.map(\.id))
        items = items.filter { ids.contains($0.key) }
        itemErrors = itemErrors.filter { ids.contains($0.key) }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: PluginHost.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(PluginHost.directory)
    }

    func isEnabled(_ plugin: Plugin) -> Bool {
        enabledIDs.contains(plugin.id)
    }

    func setEnabled(_ enabled: Bool, for plugin: Plugin) {
        if enabled {
            enabledIDs.insert(plugin.id)
        } else {
            enabledIDs.remove(plugin.id)
            items[plugin.id] = nil
            itemErrors[plugin.id] = nil
        }
        UserDefaults.standard.set(enabledIDs.sorted(), forKey: "enabledPlugins")
    }

    func refresh(_ plugin: Plugin) async {
        guard isEnabled(plugin), !loading.contains(plugin.id) else { return }
        loading.insert(plugin.id)
        defer { loading.remove(plugin.id) }
        do {
            items[plugin.id] = try await PluginHost.items(of: plugin)
            itemErrors[plugin.id] = nil
        } catch {
            itemErrors[plugin.id] = error.localizedDescription
        }
    }

    func isPerforming(_ action: PluginAction, on item: PluginItem, in plugin: Plugin) -> Bool {
        performing.contains(key(plugin.id, item.id, action.id))
    }

    func perform(_ action: PluginAction, on item: PluginItem, in plugin: Plugin) async {
        let key = key(plugin.id, item.id, action.id)
        guard isEnabled(plugin), !performing.contains(key) else { return }
        performing.insert(key)
        defer { performing.remove(key) }
        do {
            let result = try await PluginHost.perform(action.id, onItem: item.id, in: plugin)
            handle(result, from: plugin)
            if result.refresh ?? true { await refresh(plugin) }
        } catch {
            self.error = PresentedError(title: "\(action.title) Didn't Work", message: "\(plugin.manifest.name): \(error.localizedDescription)")
        }
    }

    func portActions(for port: ListeningPort) -> [(plugin: Plugin, action: PluginManifest.PortAction)] {
        enabledPlugins.flatMap { plugin in
            (plugin.manifest.portActions ?? [])
                .filter { $0.applies(toPort: port.port, processName: port.processName) }
                .map { (plugin, $0) }
        }
    }

    func perform(_ action: PluginManifest.PortAction, on port: ListeningPort, in plugin: Plugin) async {
        let key = key(plugin.id, port.id, action.id)
        guard isEnabled(plugin), !performing.contains(key) else { return }
        performing.insert(key)
        defer { performing.remove(key) }
        do {
            handle(try await PluginHost.perform(action.id, onPort: PluginPortContext(port), in: plugin), from: plugin)
        } catch {
            self.error = PresentedError(title: "\(action.title) Didn't Work", message: "\(plugin.manifest.name): \(error.localizedDescription)")
        }
    }

    private func handle(_ result: PluginActionResult, from plugin: Plugin) {
        if let url = result.open { NSWorkspace.shared.open(url) }
        if let text = result.copy { Pasteboard.copy(text) }
        if let message = result.message { notifier.post(title: plugin.manifest.name, body: message) }
    }

    private func key(_ parts: String...) -> String {
        parts.joined(separator: "\u{1F}")
    }
}
