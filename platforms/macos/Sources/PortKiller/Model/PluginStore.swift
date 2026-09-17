import AppKit
import Observation
import PortKillerKit

struct PluginRunRequest: Identifiable {
    enum Target {
        case port(ListeningPort)
        case item(PluginItem)
    }

    let id = UUID()
    let plugin: Plugin
    let actionID: String
    let title: String
    let icon: String?
    let confirmation: String?
    let inputs: [PluginInput]
    let isDestructive: Bool
    let target: Target

    var subject: String {
        switch target {
        case .port(let port): "Port \(String(port.port)) · \(port.processName)"
        case .item(let item): item.title
        }
    }

    var runTarget: PluginRun.Target {
        switch target {
        case .port(let port): .port(port.port)
        case .item(let item): .item(item.id)
        }
    }

    var inputsKey: String {
        "\(plugin.id)/\(actionID)"
    }
}

struct PluginInstallRequest: Identifiable {
    let id = UUID()
    let source: URL
    let plugin: Plugin
}

@Observable
final class PluginStore {
    let notifier: Notifier

    private(set) var plugins: [Plugin] = []
    private(set) var failures: [PluginLoadFailure] = []
    private(set) var enabledIDs: Set<Plugin.ID>
    private(set) var items: [Plugin.ID: [PluginItem]] = [:]
    private(set) var itemErrors: [Plugin.ID: String] = [:]
    private(set) var loading: Set<Plugin.ID> = []
    private(set) var activity = PluginActivity()
    private(set) var bannerRun: PluginRun.ID?
    private(set) var settingValues: [Plugin.ID: [String: String]]
    @ObservationIgnored private var rememberedInputs: [String: [String: String]]
    @ObservationIgnored private var secrets: [String: String] = [:]
    var pendingRun: PluginRunRequest?
    var presentedRun: PluginRun?
    var pendingInstall: PluginInstallRequest?
    var error: PresentedError?

    init(notifier: Notifier) {
        self.notifier = notifier
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? [])
        settingValues = UserDefaults.standard.dictionary(forKey: "pluginSettings") as? [String: [String: String]] ?? [:]
        rememberedInputs = UserDefaults.standard.dictionary(forKey: "pluginInputs") as? [String: [String: String]] ?? [:]
        reload()
    }

    var enabledPlugins: [Plugin] {
        plugins.filter { enabledIDs.contains($0.id) }
    }

    var itemPlugins: [Plugin] {
        enabledPlugins.filter { $0.manifest.items != nil }
    }

    func plugin(id: Plugin.ID) -> Plugin? {
        plugins.first { $0.id == id }
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

    func showInFinder(_ plugin: Plugin) {
        NSWorkspace.shared.activateFileViewerSelecting([plugin.bundleURL])
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

    func requestInstall(from url: URL) {
        do {
            pendingInstall = PluginInstallRequest(source: url, plugin: try PluginHost.load(url))
        } catch {
            self.error = PresentedError(title: "Couldn't Install the Plugin", message: error.localizedDescription)
        }
    }

    func install(from url: URL, enable: Bool) {
        do {
            let plugin = try PluginHost.install(url)
            reload()
            if enable { setEnabled(true, for: plugin) }
        } catch {
            self.error = PresentedError(title: "Couldn't Install the Plugin", message: error.localizedDescription)
        }
    }

    func setting(_ input: PluginInput, of plugin: Plugin) -> String {
        guard input.kind == .secret else { return settingValues[plugin.id]?[input.id] ?? input.initialValue }
        let key = "\(plugin.id)/\(input.id)"
        if let cached = secrets[key] { return cached }
        let value = PluginSecrets.value(plugin: plugin.id, key: input.id) ?? ""
        secrets[key] = value
        return value
    }

    func setSetting(_ value: String, for input: PluginInput, of plugin: Plugin) {
        if input.kind == .secret {
            secrets["\(plugin.id)/\(input.id)"] = value
            PluginSecrets.set(value, plugin: plugin.id, key: input.id)
        } else {
            settingValues[plugin.id, default: [:]][input.id] = value
            UserDefaults.standard.set(settingValues, forKey: "pluginSettings")
        }
    }

    func settings(for plugin: Plugin) -> [String: String] {
        Dictionary((plugin.manifest.settings ?? []).map { ($0.id, setting($0, of: plugin)) }) { first, _ in first }
    }

    func settingProblems(for plugin: Plugin) -> [String] {
        (plugin.manifest.settings ?? []).problems(in: settings(for: plugin))
    }

    func refresh(_ plugin: Plugin) async {
        guard isEnabled(plugin), !loading.contains(plugin.id) else { return }
        guard settingProblems(for: plugin).isEmpty else {
            itemErrors[plugin.id] = "Fill in its settings in Settings › Plugins."
            return
        }
        loading.insert(plugin.id)
        defer { loading.remove(plugin.id) }
        do {
            items[plugin.id] = try await PluginHost.items(of: plugin, settings: settings(for: plugin))
            itemErrors[plugin.id] = nil
        } catch {
            itemErrors[plugin.id] = error.localizedDescription
        }
    }

    func portActions(for port: ListeningPort) -> [(plugin: Plugin, action: PluginManifest.PortAction)] {
        enabledPlugins.flatMap { plugin in
            (plugin.manifest.portActions ?? [])
                .filter { $0.applies(toPort: port.port, processName: port.processName) }
                .map { (plugin, $0) }
        }
    }

    func isRunning(_ actionID: String, on target: PluginRun.Target, in plugin: Plugin) -> Bool {
        activity.isRunning(plugin: plugin.id, action: actionID, target: target)
    }

    func run(_ action: PluginManifest.PortAction, on port: ListeningPort, in plugin: Plugin) {
        request(PluginRunRequest(
            plugin: plugin,
            actionID: action.id,
            title: action.title,
            icon: action.icon ?? plugin.manifest.icon,
            confirmation: action.confirmation,
            inputs: action.inputs ?? [],
            isDestructive: false,
            target: .port(port)
        ))
    }

    func run(_ action: PluginAction, on item: PluginItem, in plugin: Plugin) {
        request(PluginRunRequest(
            plugin: plugin,
            actionID: action.id,
            title: action.title,
            icon: action.icon ?? plugin.manifest.icon,
            confirmation: action.confirmation,
            inputs: action.inputs ?? [],
            isDestructive: action.destructive ?? false,
            target: .item(item)
        ))
    }

    func initialInputs(for request: PluginRunRequest) -> [String: String] {
        request.inputs.values(remembered: rememberedInputs[request.inputsKey] ?? [:])
    }

    func start(_ request: PluginRunRequest, inputs: [String: String]) {
        let plugin = request.plugin
        guard isEnabled(plugin), !isRunning(request.actionID, on: request.runTarget, in: plugin) else { return }
        if !request.inputs.isEmpty {
            let secretIDs = Set(request.inputs.filter { $0.kind == .secret }.map(\.id))
            rememberedInputs[request.inputsKey] = inputs.filter { !secretIDs.contains($0.key) }
            UserDefaults.standard.set(rememberedInputs, forKey: "pluginInputs")
        }
        let runID = activity.start(PluginRun(pluginID: plugin.id, actionID: request.actionID, title: request.title, target: request.runTarget))
        let settings = settings(for: plugin)
        Task {
            do {
                let result: PluginActionResult
                switch request.target {
                case .port(let port):
                    result = try await PluginHost.perform(request.actionID, onPort: PluginPortContext(port), inputs: inputs, settings: settings, in: plugin)
                case .item(let item):
                    result = try await PluginHost.perform(request.actionID, onItem: item.id, inputs: inputs, settings: settings, in: plugin)
                }
                activity.finish(runID, as: .succeeded(result))
                handle(result, of: runID, from: plugin)
                if case .item = request.target, result.refresh ?? true {
                    await refresh(plugin)
                }
            } catch {
                activity.finish(runID, as: .failed(error.localizedDescription))
                self.error = PresentedError(title: "\(request.title.trimmingCharacters(in: ["…"])) Didn't Work", message: "\(plugin.manifest.name): \(error.localizedDescription)")
            }
        }
    }

    func dismissBanner() {
        bannerRun = nil
    }

    private func request(_ request: PluginRunRequest) {
        guard isEnabled(request.plugin), !isRunning(request.actionID, on: request.runTarget, in: request.plugin) else { return }
        let problems = settingProblems(for: request.plugin)
        guard problems.isEmpty else {
            error = PresentedError(
                title: "\(request.plugin.manifest.name) Needs Its Settings",
                message: (problems + ["Fill them in under Settings › Plugins."]).joined(separator: " ")
            )
            return
        }
        if request.inputs.isEmpty, request.confirmation == nil {
            start(request, inputs: [:])
        } else {
            pendingRun = request
        }
    }

    private func handle(_ result: PluginActionResult, of runID: PluginRun.ID, from plugin: Plugin) {
        if let url = result.open { NSWorkspace.shared.open(url) }
        if let text = result.copy { Pasteboard.copy(text) }
        if result.details != nil {
            presentedRun = activity.run(runID)
        } else if result.message != nil || result.log != nil {
            bannerRun = runID
            Task {
                try? await Task.sleep(for: .seconds(6))
                if bannerRun == runID { bannerRun = nil }
            }
        }
        if let message = result.message, !NSApp.isActive {
            notifier.post(title: plugin.manifest.name, body: message)
        }
    }
}
