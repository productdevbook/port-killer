import Foundation
import Sparkle
import AppKit
import Observation
import Combine

/**
 * UpdateManager handles automatic updates using the Sparkle framework.
 *
 * Key features:
 * - Lazy initialization (2 second delay to reduce launch memory)
 * - Only initializes when running from .app bundle (not during development)
 * - Activates app before showing update UI (important for menu bar apps)
 * - Tracks update availability and last check date
 *
 * This class uses the @Observable macro for SwiftUI reactivity and is
 * marked with @MainActor to ensure all UI updates happen on the main thread.
 */
@Observable
@MainActor
final class UpdateManager {
    // MARK: - Public Properties

    /// Whether the updater is ready to check for updates
    var canCheckForUpdates = false

    /// Timestamp of the last update check
    var lastUpdateCheckDate: Date?

    // MARK: - Private Properties

    /// Sparkle updater controller instance
    private var updaterController: SPUStandardUpdaterController?

    /// Tracks whether Sparkle has been initialized
    private var isInitialized = false

    /// Check if running from a proper app bundle (not swift run)
    private static var isRunningFromBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    // MARK: - Computed Properties

    /**
     * Whether to automatically check for updates on launch.
     * Setting this value will trigger Sparkle initialization if needed.
     */
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /**
     * Whether to automatically download updates in the background.
     * Setting this value will trigger Sparkle initialization if needed.
     */
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            ensureInitialized()
            updaterController?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    // MARK: - Initialization

    /**
     * Initializes the update manager.
     * Sparkle initialization is delayed by 2 seconds to reduce launch memory footprint.
     */
    init() {
        // Delay Sparkle initialization to reduce launch memory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.ensureInitialized()
        }
    }

    // MARK: - Private Methods

    /**
     * Ensures Sparkle is initialized before use.
     * This is called automatically when needed and is safe to call multiple times.
     * Skips initialization when not running from an .app bundle (development mode).
     */
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

        // Observe Sparkle properties and update our @Observable properties
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
            }
            .store(in: &cancellables)
    }

    /// Storage for Combine cancellables
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    // MARK: - Public Methods

    /**
     * Manually checks for updates.
     * Activates the app and brings the update window to the front.
     * This is important for menu bar apps that don't normally have visible windows.
     */
    func checkForUpdates() {
        ensureInitialized()
        guard let controller = updaterController else { return }
        // Activate app to ensure Sparkle window appears in front
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
