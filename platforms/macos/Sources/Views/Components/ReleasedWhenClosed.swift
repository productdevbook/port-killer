import SwiftUI
import AppKit

/// Builds a window's content only while that window is open.
///
/// SwiftUI keeps a closed `Window` scene's view hierarchy alive, so a window
/// opened once kept ~40 MB in memory for the rest of the session. Dropping
/// the content on close lets the menu-bar-only app return to a small
/// baseline; it is rebuilt from `AppState` when the window reopens.
///
/// AppKit window notifications are used because `onDisappear` does not fire
/// reliably for repeated close/reopen cycles of the same scene.
struct ReleasedWhenClosed<Content: View>: View {
    /// Title of the hosting window (matches the `Window` scene title)
    let windowTitle: String
    @ViewBuilder let content: () -> Content

    @State private var isOpen = true

    var body: some View {
        ZStack {
            if isOpen {
                content()
            }
        }
        .onAppear { isOpen = true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if isHostWindow(note) { isOpen = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            if isHostWindow(note), let window = note.object as? NSWindow,
               window.occlusionState.contains(.visible) {
                isOpen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if isHostWindow(note) { isOpen = true }
        }
    }

    private func isHostWindow(_ note: Notification) -> Bool {
        (note.object as? NSWindow)?.title == windowTitle
    }
}
