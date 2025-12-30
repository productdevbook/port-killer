/// MenuBarActions - Action buttons at bottom of menu bar
///
/// Provides menu items for:
/// - Opening main window
/// - Refresh, view toggle
/// - Kill all processes
/// - Settings and quit actions
///
/// - Note: Uses MenuItemButton for consistent styling.
/// - Important: Handles window activation for menu bar apps.

import SwiftUI

struct MenuBarActions: View {
    @Binding var confirmingKillAll: Bool
    @Binding var useTreeView: Bool
    @Bindable var state: AppState
    let openWindow: OpenWindowAction

    var body: some View {
        VStack(spacing: 0) {
            MenuItemButton(title: "Refresh", icon: "arrow.clockwise", shortcut: "R") {
                Task { await state.refresh() }
            }

            MenuItemButton(
                title: useTreeView ? "List View" : "Tree View",
                icon: useTreeView ? "list.bullet" : "list.bullet.indent",
                shortcut: "T"
            ) {
                useTreeView.toggle()
            }

            if confirmingKillAll {
                HStack {
                    Text("Kill all \(state.ports.count) processes?")
                        .font(.callout)
                    Spacer()
                    Button("Kill") {
                        Task { await state.killAll() }
                        confirmingKillAll = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    Button("Cancel") { confirmingKillAll = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                MenuItemButton(title: "Kill All", icon: "xmark.circle", shortcut: "K", isDestructive: true) {
                    confirmingKillAll = true
                }
                .disabled(state.ports.isEmpty)
            }

            Divider()
                .padding(.vertical, 4)

            MenuItemButton(title: "Open PortKiller", icon: "macwindow", shortcut: "O") {
                openWindow(id: "main")
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    bringMainWindowToFront()
                }
            }

            MenuItemButton(title: "Settings...", icon: "gear", shortcut: ",") {
                state.selectedSidebarItem = .settings
                openWindow(id: "main")
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    bringMainWindowToFront()
                }
            }

            MenuItemButton(title: "Quit PortKiller", icon: "power", shortcut: "Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Menu Item Button

/// Styled button component for menu bar actions
struct MenuItemButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Text(title)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
                if let shortcut = shortcut {
                    Text("⌘\(shortcut)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor : Color.clear)
            .foregroundStyle(isHovered ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Helper Functions

/// Brings the main window to front for menu bar apps
@MainActor
private func bringMainWindowToFront() {
    // For menu bar apps, we need to set activation policy to regular temporarily
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Find the main window (not menu bar extra)
    for window in NSApp.windows {
        // Skip menu bar extra windows
        if window.level == .popUpMenu || window.level == .statusBar {
            continue
        }
        if window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
    }
}
