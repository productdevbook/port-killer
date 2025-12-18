import SwiftUI

struct TunnelStatusBadge: View {
    let tunnel: CloudflareTunnelState
    let onCopyURL: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            if tunnel.status == .active, let url = tunnel.tunnelURL {
                // Show shortened URL
                Text(shortenedURL(url))
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Button {
                    onCopyURL()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copy tunnel URL")

                Button {
                    onStop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop tunnel")
            } else if tunnel.status == .starting {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Starting tunnel...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if tunnel.status == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(tunnel.lastError ?? "Tunnel error")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Button {
                    onStop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusBackgroundColor.opacity(0.1))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .idle: .secondary
        case .starting: .yellow
        case .active: .green
        case .stopping: .yellow
        case .error: .red
        }
    }

    private var statusBackgroundColor: Color {
        switch tunnel.status {
        case .idle: .secondary
        case .starting: .blue
        case .active: .blue
        case .stopping: .blue
        case .error: .red
        }
    }

    private func shortenedURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
