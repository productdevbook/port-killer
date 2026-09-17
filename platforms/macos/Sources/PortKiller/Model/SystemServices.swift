import AppKit
import Observation
import PortKillerKit
import ServiceManagement
import Sparkle

@Observable
final class ToolInstaller {
    let preferences: Preferences
    private(set) var installing: Set<String> = []
    private(set) var errors: [String: String] = [:]

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var canInstall: Bool {
        _ = preferences.toolsRevision
        return CommandLineTool.brew.locate() != nil
    }

    func install(_ tool: CommandLineTool) {
        guard let brew = CommandLineTool.brew.locate(), !installing.contains(tool.name) else { return }
        installing.insert(tool.name)
        errors[tool.name] = nil
        Task(name: "Install \(tool.name)") {
            defer {
                installing.remove(tool.name)
                preferences.toolsChanged()
            }
            do {
                let result = try await CommandRunner.run(brew, ["install", tool.formula])
                if !result.succeeded { errors[tool.name] = String(result.combined.suffix(300)) }
            } catch {
                errors[tool.name] = error.localizedDescription
            }
        }
    }
}

@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    var error: String?

    var isEnabled: Bool {
        get { status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            refresh()
        }
    }

    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@Observable
final class Updater {
    private(set) var canCheckForUpdates = false
    private(set) var lastCheck: Date?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var automaticallyDownloads: Bool {
        get {
            access(keyPath: \.automaticallyDownloads)
            return controller?.updater.automaticallyDownloadsUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyDownloads) {
                controller?.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    func start() {
        guard controller == nil, AppInfo.isBundled else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        lastCheck = controller.updater.lastUpdateCheckDate
        observations = [
            controller.updater.observe(\.canCheckForUpdates) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
            controller.updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in
                Task { @MainActor in self?.syncState() }
            },
        ]
    }

    private func syncState() {
        canCheckForUpdates = controller?.updater.canCheckForUpdates ?? false
        lastCheck = controller?.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

enum AppInfo {
    static let isBundled = Bundle.main.bundleURL.pathExtension == "app"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    static let repository = URL(string: "https://github.com/productdevbook/port-killer")
    static let issues = URL(string: "https://github.com/productdevbook/port-killer/issues")
    static let sponsors = URL(string: "https://github.com/sponsors/productdevbook")
    static let twitter = URL(string: "https://x.com/productdevbook")
}
