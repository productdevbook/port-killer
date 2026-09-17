import AppKit
import Observation
import PortKillerKit

struct PluginRunRequest: Identifiable {
    enum Target {
        case port(Int, listener: ListeningPort?)
        case item(PluginItem)
        case nothing
    }

    enum Purpose {
        case run(node: PluginNode?)
        case create(connectTo: Int?)
        case edit(PluginNode)
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
    var purpose: Purpose = .run(node: nil)

    var subject: String {
        switch target {
        case .port(let port, let listener): ["Port \(String(port))", listener?.processName].compactMap { $0 }.joined(separator: " · ")
        case .item(let item): item.title
        case .nothing: plugin.manifest.name
        }
    }

    var runTarget: PluginRun.Target? {
        switch target {
        case .port(let port, _): .port(port)
        case .item(let item): .item(item.id)
        case .nothing: nil
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
    private(set) var nodes: PluginNodes
    private(set) var settingValues: [Plugin.ID: [String: String]]
    @ObservationIgnored private var rememberedInputs: [String: [String: String]]
    @ObservationIgnored private var secrets: [String: String] = [:]
    @ObservationIgnored private let ports: PortStore
    @ObservationIgnored private var nodeMonitor = WatchMonitor()
    var pendingRun: PluginRunRequest?
    var presentedRun: PluginRun?
    var pendingInstall: PluginInstallRequest?
    var error: PresentedError?

    init(notifier: Notifier, ports: PortStore) {
        self.notifier = notifier
        self.ports = ports
        nodes = PluginNodes(UserDefaults.standard.decodedValue(of: [PluginNode].self, forKey: "pluginNodes") ?? [])
        enabledIDs = Set(UserDefaults.standard.stringArray(forKey: "enabledPlugins") ?? [])
        settingValues = UserDefaults.standard.dictionary(forKey: "pluginSettings") as? [String: [String: String]] ?? [:]
        rememberedInputs = UserDefaults.standard.dictionary(forKey: "pluginInputs") as? [String: [String: String]] ?? [:]
        reload()
        ports.onScan = { [weak self] scanned in self?.portsScanned(scanned) }
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

    var nodeTypes: [(plugin: Plugin, action: PluginManifest.PortAction)] {
        enabledPlugins.flatMap { plugin in (plugin.manifest.portActions ?? []).map { (plugin, $0) } }
    }

    func run(_ action: PluginManifest.PortAction, on port: ListeningPort, in plugin: Plugin) {
        request(portRequest(action, port: port.port, listener: port, in: plugin))
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

    func addNode(_ action: PluginManifest.PortAction, in plugin: Plugin, connectTo port: Int? = nil) {
        var request = PluginRunRequest(
            plugin: plugin,
            actionID: action.id,
            title: action.title,
            icon: action.icon ?? plugin.manifest.icon,
            confirmation: nil,
            inputs: action.inputs ?? [],
            isDestructive: false,
            target: port.map { .port($0, listener: listener(on: $0)) } ?? .nothing
        )
        request.purpose = .create(connectTo: port)
        pendingRun = request
    }

    func edit(_ node: PluginNode) {
        guard let (plugin, action) = pluginAction(for: node) else { return }
        pendingRun = PluginRunRequest(
            plugin: plugin,
            actionID: action.id,
            title: action.title,
            icon: action.icon ?? plugin.manifest.icon,
            confirmation: nil,
            inputs: action.inputs ?? [],
            isDestructive: false,
            target: .nothing,
            purpose: .edit(node)
        )
    }

    func duplicate(_ node: PluginNode) {
        guard let copy = nodes.duplicate(node.id, named: "\(node.name) Copy") else { return }
        nodes.save(copy)
        saveNodes()
    }

    func delete(_ node: PluginNode) {
        nodes.remove(node.id)
        saveNodes()
    }

    func connect(_ id: PluginNode.ID, to port: Int) {
        nodes.connect(id, to: port)
        saveNodes()
    }

    func disconnect(_ id: PluginNode.ID, from port: Int) {
        nodes.disconnect(id, from: port)
        saveNodes()
    }

    func setRunsWhenPortStarts(_ runs: Bool, for node: PluginNode) {
        var node = node
        node.runsWhenPortStarts = runs
        nodes.save(node)
        saveNodes()
    }

    func run(_ node: PluginNode, on port: Int) {
        guard let (plugin, action) = pluginAction(for: node) else { return }
        var request = portRequest(action, port: port, listener: listener(on: port), in: plugin)
        request.purpose = .run(node: node)
        if request.confirmation == nil {
            start(request, inputs: node.inputs, node: node.id)
        } else {
            self.request(request)
        }
    }

    func run(_ node: PluginNode) {
        let listening = node.ports.filter { listener(on: $0) != nil }
        guard !listening.isEmpty else {
            error = PresentedError(
                title: "\(node.name) Didn't Run",
                message: node.ports.isEmpty ? "Drag a port onto the node to connect it first." : "None of its ports are listening right now."
            )
            return
        }
        for port in listening {
            run(node, on: port)
        }
    }

    func pluginAction(for node: PluginNode) -> (plugin: Plugin, action: PluginManifest.PortAction)? {
        guard let plugin = enabledPlugins.first(where: { $0.id == node.pluginID }),
              let action = plugin.manifest.portActions?.first(where: { $0.id == node.actionID })
        else { return nil }
        return (plugin, action)
    }

    func initialInputs(for request: PluginRunRequest) -> [String: String] {
        switch request.purpose {
        case .edit(let node), .run(node: .some(let node)):
            request.inputs.values(remembered: node.inputs)
        case .create, .run(node: nil):
            request.inputs.values(remembered: rememberedInputs[request.inputsKey] ?? [:])
        }
    }

    func submit(_ request: PluginRunRequest, inputs: [String: String], name: String = "", runsWhenPortStarts: Bool = false, connects: Bool = true) {
        switch request.purpose {
        case .run(let node):
            start(request, inputs: inputs, node: node?.id)
        case .create(let port):
            rememberInputs(inputs, for: request)
            nodes.save(PluginNode(
                pluginID: request.plugin.id,
                actionID: request.actionID,
                name: name,
                inputs: inputs,
                ports: connects ? port.map { [$0] } ?? [] : [],
                runsWhenPortStarts: runsWhenPortStarts
            ))
            saveNodes()
        case .edit(var node):
            node.name = name
            node.inputs = inputs
            node.runsWhenPortStarts = runsWhenPortStarts
            nodes.save(node)
            saveNodes()
        }
    }

    func start(_ request: PluginRunRequest, inputs: [String: String], node: PluginNode.ID? = nil) {
        let plugin = request.plugin
        guard let runTarget = request.runTarget, isEnabled(plugin), !isRunning(request.actionID, on: runTarget, in: plugin) else { return }
        let problems = settingProblems(for: plugin)
        guard problems.isEmpty else {
            error = PresentedError(
                title: "\(plugin.manifest.name) Needs Its Settings",
                message: (problems + ["Fill them in under Settings › Plugins."]).joined(separator: " ")
            )
            return
        }
        if node == nil {
            rememberInputs(inputs, for: request)
        }
        let title = node.flatMap { nodes.node($0)?.name } ?? request.title
        let runID = activity.start(PluginRun(pluginID: plugin.id, actionID: request.actionID, nodeID: node, title: title, target: runTarget))
        let settings = settings(for: plugin)
        Task {
            do {
                let result: PluginActionResult
                switch request.target {
                case .port(let port, let listener):
                    guard let listener = listener ?? self.listener(on: port) else {
                        throw PluginError.failed(status: 0, message: "Nothing is listening on port \(port) right now.")
                    }
                    result = try await PluginHost.perform(request.actionID, onPort: PluginPortContext(listener), inputs: inputs, node: node, settings: settings, in: plugin)
                case .item(let item):
                    result = try await PluginHost.perform(request.actionID, onItem: item.id, inputs: inputs, settings: settings, in: plugin)
                case .nothing:
                    return
                }
                activity.finish(runID, as: .succeeded(result))
                handle(result, of: runID, from: plugin)
                if case .item = request.target, result.refresh ?? true {
                    await refresh(plugin)
                }
            } catch {
                activity.finish(runID, as: .failed(error.localizedDescription))
                self.error = PresentedError(title: "\(title.trimmingCharacters(in: ["…"])) Didn't Work", message: "\(plugin.manifest.name): \(error.localizedDescription)")
            }
        }
    }

    func dismissBanner() {
        bannerRun = nil
    }

    private func portRequest(_ action: PluginManifest.PortAction, port: Int, listener: ListeningPort?, in plugin: Plugin) -> PluginRunRequest {
        PluginRunRequest(
            plugin: plugin,
            actionID: action.id,
            title: action.title,
            icon: action.icon ?? plugin.manifest.icon,
            confirmation: action.confirmation,
            inputs: action.inputs ?? [],
            isDestructive: false,
            target: .port(port, listener: listener)
        )
    }

    private func listener(on port: Int) -> ListeningPort? {
        ports.ports.first { $0.port == port }
    }

    private func saveNodes() {
        UserDefaults.standard.setEncodedValue(nodes.all, forKey: "pluginNodes")
    }

    private func rememberInputs(_ inputs: [String: String], for request: PluginRunRequest) {
        guard !request.inputs.isEmpty else { return }
        let secretIDs = Set(request.inputs.filter { $0.kind == .secret }.map(\.id))
        rememberedInputs[request.inputsKey] = inputs.filter { !secretIDs.contains($0.key) }
        UserDefaults.standard.set(rememberedInputs, forKey: "pluginInputs")
    }

    private func portsScanned(_ scanned: [ListeningPort]) {
        let events = nodeMonitor.events(watched: nodes.watchedPorts, ports: scanned)
        for (node, port) in nodes.triggered(by: events) {
            guard let (plugin, action) = pluginAction(for: node) else { continue }
            var request = portRequest(action, port: port, listener: scanned.first { $0.port == port }, in: plugin)
            request.purpose = .run(node: node)
            start(request, inputs: node.inputs, node: node.id)
        }
    }

    private func request(_ request: PluginRunRequest) {
        guard isEnabled(request.plugin) else { return }
        if let target = request.runTarget, isRunning(request.actionID, on: target, in: request.plugin) { return }
        let problems = settingProblems(for: request.plugin)
        guard problems.isEmpty else {
            error = PresentedError(
                title: "\(request.plugin.manifest.name) Needs Its Settings",
                message: (problems + ["Fill them in under Settings › Plugins."]).joined(separator: " ")
            )
            return
        }
        if request.inputs.isEmpty, request.confirmation == nil {
            submit(request, inputs: [:])
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
