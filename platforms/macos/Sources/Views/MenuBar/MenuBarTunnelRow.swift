import SwiftUI

struct MenuBarTunnelRow: View {
    let tunnel: CloudflareTunnelState
    @Bindable var state: AppState
    @State private var isHovered = false
    @State private var isCopied = false

    private var statusColor: Color {
        switch tunnel.status {
        case .idle: .secondary.opacity(0.3)
        case .starting: .orange
        case .active: .green
        case .stopping: .orange
        case .error: .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
                .shadow(color: tunnel.status == .active ? .green.opacity(0.5) : .clear, radius: 3)
            Text(":" + String(tunnel.port))
                .font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                .frame(width: 55, alignment: .leading)

            if let url = tunnel.tunnelURL {
                Text(shortenedURL(url))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            } else if tunnel.status == .starting {
                Text("Starting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if tunnel.status == .error {
                Text("Error")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            if tunnel.status == .active, tunnel.tunnelURL != nil {
                Button {
                    if let url = tunnel.tunnelURL {
                        ClipboardService.copy(url)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            isCopied = false
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .opacity(isHovered ? 1 : 0.6)
            } else if tunnel.status == .starting {
                ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
            }

            Button {
                state.tunnelManager.stopTunnel(id: tunnel.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if tunnel.status == .active, let url = tunnel.tunnelURL {
                Button {
                    ClipboardService.copy(url)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                }
                Button {
                    if let tunnelURL = URL(string: url) {
                        NSWorkspace.shared.open(tunnelURL)
                    }
                } label: {
                    Label("Open in Browser", systemImage: "globe.fill")
                }
                Divider()
            }
            Button(role: .destructive) {
                state.tunnelManager.stopTunnel(id: tunnel.id)
            } label: {
                Label("Stop Tunnel", systemImage: "stop.fill")
            }
        }
    }

    private func shortenedURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
