import AppKit
import PortKillerKit
import SwiftUI

@main
struct PortKillerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("PortKiller", id: "main") {
            MainView()
                .environment(appDelegate.model)
        }
        .defaultSize(width: 1180, height: 720)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(appDelegate.model.preferences.hasCompletedOnboarding ? .suppressed : .presented)
        .commands {
            PortKillerCommands(model: appDelegate.model)
        }

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }

        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var windowObservations: [NotificationCenter.ObservationToken] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        model.start()
        windowObservations = [
            NotificationCenter.default.addObserver(of: NSWindow.self, for: .didBecomeKey) { message in
                guard Self.isDocumentWindow(message.window) else { return }
                NSApp.setActivationPolicy(.regular)
            },
            NotificationCenter.default.addObserver(of: NSWindow.self, for: .willClose) { message in
                let closing = message.window
                guard Self.isDocumentWindow(closing) else { return }
                let othersVisible = NSApp.windows.contains { $0 !== closing && $0.isVisible && Self.isDocumentWindow($0) }
                if !othersVisible { NSApp.setActivationPolicy(.accessory) }
            },
        ]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.show()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task(name: "Shut down") {
            await model.shutDown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private static func isDocumentWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.level == .normal
    }
}

struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let image = Self.icon {
                Image(nsImage: image)
            } else {
                Image(systemName: "powerplug")
            }
        }
        .onAppear { model.openWindow = openWindow }
    }

    private static let icon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "ToolbarIcon") else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
