/// PortListRow - Individual port row component for table view
///
/// Displays comprehensive port information in a table row:
/// - Favorite star toggle
/// - Status indicator (active/inactive)
/// - Port number (monospaced)
/// - Process name with icon
/// - PID, type badge, address, user
/// - Action buttons (watch, kill/remove)
///
/// - Note: Includes context menu for quick actions.
/// - Important: Shows different actions for active vs inactive ports.

import SwiftUI

struct PortListRow: View {
    let port: PortInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Favorite
            Button {
                appState.toggleFavorite(port.port)
            } label: {
                Image(systemName: appState.isFavorite(port.port) ? "star.fill" : "star")
                    .foregroundStyle(appState.isFavorite(port.port) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle favorite")
            .frame(width: 40, alignment: .center)

            // Status indicator
            Circle()
                .fill(port.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.trailing, 8)

            // Port
            Text(String(port.port))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 70, alignment: .leading)
                .opacity(port.isActive ? 1 : 0.6)

            // Process
            HStack(spacing: 6) {
                Image(systemName: port.processType.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(port.processName)
                    .lineLimit(1)
                    .foregroundStyle(port.isActive ? .primary : .secondary)
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            // PID
            Text(port.isActive ? String(port.pid) : "-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Type
            if port.isActive {
                Text(port.processType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            } else {
                Text("Inactive")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            }

            // Address
            Text(port.address)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // User
            Text(port.user)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button {
                    appState.toggleWatch(port.port)
                } label: {
                    Image(systemName: appState.isWatching(port.port) ? "eye.fill" : "eye")
                        .foregroundStyle(appState.isWatching(port.port) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle watch")

                if port.isActive {
                    Button {
                        Task {
                            await appState.killPort(port)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Kill process (Delete)")
                } else {
                    Button {
                        // Remove from favorites/watched
                        if appState.isFavorite(port.port) {
                            appState.favorites.remove(port.port)
                        }
                        if appState.isWatching(port.port) {
                            appState.toggleWatch(port.port)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from list")
                }
            }
            .frame(width: 80)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
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

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(port.port), forType: .string)
            } label: {
                Label("Copy Port Number", systemImage: "doc.on.doc")
            }

            if port.isActive {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(port.command, forType: .string)
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    Task {
                        await appState.killPort(port)
                    }
                } label: {
                    Label("Kill Process", systemImage: "xmark.circle")
                }
                .keyboardShortcut(.delete, modifiers: [])
            }

            Divider()
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

            // Tunnel section
            if port.isActive {
                Divider()

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
    }

    /// Returns color for process type badge
    private var typeColor: Color {
        switch port.processType {
        case .webServer: return .blue
        case .database: return .purple
        case .development: return .orange
        case .system: return .gray
        case .other: return .secondary
        }
    }
}
