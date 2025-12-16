import SwiftUI

@main
struct PortKillerApp: App {
    @State private var manager = PortManager()

    init() {
        // Hide from Dock
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Image(nsImage: menuBarIcon())
        }
        .menuBarExtraStyle(.window)
    }

    private func menuBarIcon() -> NSImage {
        if let url = Bundle.module.url(forResource: "ToolbarIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "network.slash", accessibilityDescription: nil) ?? NSImage()
    }
}
