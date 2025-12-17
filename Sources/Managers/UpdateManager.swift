import Foundation
import Sparkle
import AppKit

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    private var updaterController: SPUStandardUpdaterController?
    private var isInitialized = false

    @Published var canCheckForUpdates = false
    @Published var lastUpdateCheckDate: Date?

    /// Check if running from a proper app bundle (not swift run)
    private static var isRunningFromBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { updaterController?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    override init() {
        super.init()
        // Delay Sparkle initialization to reduce launch memory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ensureInitialized()
        }
    }

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = true

        guard Self.isRunningFromBundle else {
            #if DEBUG
            print("[UpdateManager] Skipping Sparkle initialization (not running from .app bundle)")
            #endif
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    func checkForUpdates() {
        ensureInitialized()
        guard let controller = updaterController else { return }
        // Activate app to ensure Sparkle window appears in front
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
