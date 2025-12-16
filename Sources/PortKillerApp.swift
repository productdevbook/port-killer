import SwiftUI

@main
struct PortKillerApp: App {
    @State private var state = AppState()

    init() {
        // Disable automatic window tabbing (prevents Chrome-like tabs)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        // Main Window - Single instance only
        Window("PortKiller", id: "main") {
            MainWindowView()
                .environment(state)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {} // Disable Cmd+N
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
               FileManager.default.fileExists(atPath: url.path),
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
