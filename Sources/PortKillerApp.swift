import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as accessory (menu bar only, no Dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Initialize notification service for watched port alerts
        NotificationService.shared.setup()

        // Monitor window visibility to toggle Dock icon
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == "PortKiller" else { return }
        // Show in Dock when main window is open
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.title == "PortKiller" else { return }
        // Hide from Dock when main window closes
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PortKillerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()
    @State private var sponsorManager = SponsorManager()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Disable automatic window tabbing (prevents Chrome-like tabs)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // Main Window - Single instance only
        Window("PortKiller", id: "main") {
            MainWindowView()
                .environment(state)
                .environment(sponsorManager)
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    sponsorManager.checkAndShowIfNeeded()
                }
                .onChange(of: sponsorManager.shouldShowWindow) { _, shouldShow in
                    if shouldShow {
                        state.selectedSidebarItem = .sponsors
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "main")
                        sponsorManager.markWindowShown()
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {} // Disable Cmd+N

            CommandGroup(after: .appInfo) {
				Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") {
					state.updateManager.checkForUpdates()
				}
				.disabled(!state.updateManager.canCheckForUpdates)
            }
        }

        // Menu Bar (quick access)
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(nsImage: menuBarIcon())
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarIcon() -> NSImage {
        // Try various bundle paths for icon
        let paths = [
            Bundle.main.resourceURL?.appendingPathComponent("PortKiller_PortKiller.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("PortKiller_PortKiller.bundle"),
            Bundle.main.resourceURL,
            Bundle.main.bundleURL
        ]
        for p in paths {
            if let url = p?.appendingPathComponent("ToolbarIcon@2x.png"),
               FileManager.default.fileExists(atPath: url.path()),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true  // Enable template mode for monochrome menu bar icon
                return img
            }
        }
        // Fallback to system icon
        return NSImage(systemSymbolName: "network", accessibilityDescription: "PortKiller") ?? NSImage()
    }
}
