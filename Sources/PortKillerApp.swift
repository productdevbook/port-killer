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
          Image("ToolbarIcon", bundle: .module)
        }
        .menuBarExtraStyle(.window)
    }
}
