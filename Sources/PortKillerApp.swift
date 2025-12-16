import SwiftUI

@main
struct PortKillerApp: App {
    @State private var state = AppState()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            Image(nsImage: menuBarIcon())
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(state: state)
        }
        .windowResizability(.contentSize)
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
               FileManager.default.fileExists(atPath: url.path),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }
        // Fallback to system icon
        return NSImage(systemSymbolName: "network", accessibilityDescription: "PortKiller") ?? NSImage()
    }
}
