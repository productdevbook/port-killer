/**
 * PortContextMenu.swift
 * PortKiller
 *
 * Shared context menu for port rows across the app.
 * Provides consistent actions for favorites, watching, clipboard, browser, tunnels, and kill.
 */

import SwiftUI

/// Configuration for PortContextMenu to enable/disable specific sections
struct PortContextMenuOptions {
    var includeCopyPortNumber: Bool = true
    var includeCopyCommand: Bool = true
    var includeKillAction: Bool = true
    var includeTunnelActions: Bool = true
    var includeBrowserActions: Bool = true

    static let full = PortContextMenuOptions()
    static let minimal = PortContextMenuOptions(
        includeCopyPortNumber: false,
        includeCopyCommand: false,
        includeKillAction: false,
        includeTunnelActions: false
    )
    static let menuBar = PortContextMenuOptions(
        includeCopyPortNumber: false,
        includeCopyCommand: false,
        includeKillAction: false
    )
    static let nested = PortContextMenuOptions(
        includeCopyPortNumber: false,
        includeCopyCommand: false,
        includeKillAction: false
    )
}

/// Shared context menu component for port actions
struct PortContextMenu: View {
    let port: PortInfo
    let options: PortContextMenuOptions

    @Environment(AppState.self) private var appState

    init(port: PortInfo, options: PortContextMenuOptions = .full) {
        self.port = port
        self.options = options
    }

    var body: some View {
        Group {
            // Favorite & Watch Section
            favoriteWatchSection

            // Copy Section
            if options.includeCopyPortNumber || (options.includeCopyCommand && port.isActive) {
                Divider()
                copySection
            }

            // Process Type Override
            if port.isActive {
                Divider()
                processTypeSection
            }

            // Kill Action
            if options.includeKillAction && port.isActive {
                Divider()
                killSection
            }

            // Browser Section
            if options.includeBrowserActions {
                Divider()
                browserSection
            }

            // Tunnel Section
            if options.includeTunnelActions && port.isActive {
                Divider()
                tunnelSection
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var favoriteWatchSection: some View {
        Button {
            appState.toggleFavorite(port.port)
        } label: {
            Label(
                appState.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites",
                systemImage: appState.isFavorite(port.port) ? "star.slash" : "star"
            )
        }

        Button {
            appState.toggleWatch(port.port)
        } label: {
            Label(
                appState.isWatching(port.port) ? "Stop Watching" : "Watch Port",
                systemImage: appState.isWatching(port.port) ? "eye.slash" : "eye"
            )
        }
    }

    @ViewBuilder
    private var processTypeSection: some View {
        Menu {
            ForEach(ProcessType.allCases) { type in
                Button {
                    appState.setProcessTypeOverride(processName: port.processName, type: type)
                } label: {
                    HStack {
                        Label(type.rawValue, systemImage: type.icon)
                        if port.processType == type {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            if appState.processTypeOverride(for: port.processName) != nil {
                Divider()
                Button {
                    appState.clearProcessTypeOverride(processName: port.processName)
                } label: {
                    Label("Reset to Auto", systemImage: "arrow.counterclockwise")
                }
            }
        } label: {
            Label("Set Process Type", systemImage: "tag")
        }
    }

    @ViewBuilder
    private var copySection: some View {
        if options.includeCopyPortNumber {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(port.port), forType: .string)
            } label: {
                Label("Copy Port Number", systemImage: "doc.on.doc")
            }
        }

        if options.includeCopyCommand && port.isActive {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(port.command, forType: .string)
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var killSection: some View {
        Button(role: .destructive) {
            Task {
                await appState.killPort(port)
            }
        } label: {
            Label("Kill Process", systemImage: "xmark.circle")
        }
        .keyboardShortcut(.delete, modifiers: [])
    }

    @ViewBuilder
    private var browserSection: some View {
        Button {
            if let url = URL(string: "http://localhost:\(port.port)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Open in Browser", systemImage: "globe.fill")
        }
        .keyboardShortcut("o", modifiers: .command)

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
        } label: {
            Label("Copy URL", systemImage: "document.on.clipboard")
        }
    }

    @ViewBuilder
    private var tunnelSection: some View {
        if appState.tunnelManager.isCloudflaredInstalled {
            if let tunnel = appState.tunnelManager.tunnelState(for: port.port) {
                if tunnel.status == .active, let url = tunnel.tunnelURL {
                    Button {
                        ClipboardService.copy(url)
                    } label: {
                        Label("Copy Tunnel URL", systemImage: "doc.on.doc")
                    }

                    Button {
                        if let tunnelURL = URL(string: url) {
                            NSWorkspace.shared.open(tunnelURL)
                        }
                    } label: {
                        Label("Open Tunnel URL", systemImage: "globe")
                    }
                }

                Button {
                    appState.tunnelManager.stopTunnel(for: port.port)
                } label: {
                    Label("Stop Tunnel", systemImage: "icloud.slash")
                }
            } else {
                Button {
                    appState.tunnelManager.startTunnel(for: port.port, portInfoId: port.id)
                } label: {
                    Label("Share via Tunnel", systemImage: "cloud.fill")
                }
            }
        } else {
            Button {
                ClipboardService.copy("brew install cloudflared")
            } label: {
                Label("Copy: brew install cloudflared", systemImage: "doc.on.doc")
            }
        }
    }
}
