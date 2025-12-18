import SwiftUI

struct TunnelStatusBadge: View {
    let tunnel: CloudflareTunnelState
    let onCopyURL: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Main content area
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                if tunnel.status == .active, let url = tunnel.tunnelURL {
                    Text(shortenedURL(url))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else if tunnel.status == .starting || tunnel.status == .stopping {
                    ProgressView()
                        .controlSize(.small)
                    Text(tunnel.status == .starting ? "Starting tunnel..." : "Stopping...")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if tunnel.status == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(tunnel.lastError ?? "Tunnel error")
                        .font(.body)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            if tunnel.status == .active {
                Button {
                    onCopyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy tunnel URL")
            }

            Button {
                onStop()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(tunnel.status == .active ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .help(tunnel.status == .error ? "Dismiss" : "Stop tunnel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .idle: .secondary
        case .starting: .orange
        case .active: .green
        case .stopping: .orange
        case .error: .red
        }
    }

    private func shortenedURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
