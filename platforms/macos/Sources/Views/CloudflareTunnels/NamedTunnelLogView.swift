import SwiftUI

/// Scrolling, auto-following log console for a named Cloudflare tunnel.
struct NamedTunnelLogView: View {
    let tunnel: NamedCloudflareTunnel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(tunnel.logs) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.timestamp, style: .time)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.black.opacity(0.85))
            .onChange(of: tunnel.logs.count) { _, _ in
                if let last = tunnel.logs.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for level: TunnelLogEntry.LogLevel) -> Color {
        switch level {
        case .info: .white.opacity(0.85)
        case .warning: .orange
        case .error: .red
        case .request: .cyan
        }
    }
}
