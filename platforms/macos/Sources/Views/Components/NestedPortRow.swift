/// NestedPortRow - Individual port row within expanded process group
///
/// Displays port information nested under a process group:
/// - Indented layout with tree connector
/// - Port number and status
/// - Favorite and watch indicators
/// - Process type badge
/// - Address and user information
/// - Action buttons (favorite, watch, kill)
///
/// - Note: Used in tree view when process groups are expanded.
/// - Important: Context menu provides quick access to common actions.

import SwiftUI

struct NestedPortListRow: View {
    let port: PortInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Indent spacing (aligned with Port column)
            HStack(spacing: 4) {
                Color.clear.frame(width: 20)

                // Status indicator
                Circle()
                    .fill(port.isActive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text(String(port.port))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .frame(width: 70 + 20, alignment: .leading)
            .padding(.leading, 24)

            // Process (Empty for nested, or maybe protocol?)
            Text("└─")
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)

            HStack(spacing: 4) {
                if appState.isFavorite(port.port) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if appState.isWatching(port.port) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 130, alignment: .leading)

            // PID (Already shown in group, so dash or blank)
            Text("-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            // Type
            if port.isActive {
                Text(port.processType.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            } else {
                Spacer().frame(width: 100)
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
                    appState.toggleFavorite(port.port)
                } label: {
                    Image(systemName: appState.isFavorite(port.port) ? "star.fill" : "star")
                        .foregroundStyle(appState.isFavorite(port.port) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)

                Button {
                    appState.toggleWatch(port.port)
                } label: {
                    Image(systemName: appState.isWatching(port.port) ? "eye.fill" : "eye")
                        .foregroundStyle(appState.isWatching(port.port) ? .blue : .secondary)
                }
                .buttonStyle(.plain)

                if port.isActive {
                    Button {
                        Task { await appState.killPort(port) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 80)
            .opacity(isHovered ? 1 : 0)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button { appState.toggleFavorite(port.port) } label: {
                Label(appState.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: appState.isFavorite(port.port) ? "star.slash" : "star")
            }
            Button { appState.toggleWatch(port.port) } label: {
                Label(appState.isWatching(port.port) ? "Stop Watching" : "Watch Port",
                      systemImage: appState.isWatching(port.port) ? "eye.slash" : "eye")
            }
            Divider()
            Button {
                if let url = URL(string: "http://localhost:\(port.port)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "globe")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
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
