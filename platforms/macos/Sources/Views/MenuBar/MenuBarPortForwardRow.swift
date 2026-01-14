import SwiftUI

struct MenuBarPortForwardRow: View {
    let connection: PortForwardConnectionState
    @Bindable var state: AppState
    @State private var isHovered = false

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        }
        return .secondary.opacity(0.3)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
                .shadow(color: connection.isFullyConnected ? .green.opacity(0.5) : .clear, radius: 3)
            Text(":" + String(connection.effectivePort))
                .font(.system(.callout, design: .monospaced)).fontWeight(.medium)
                .frame(width: 55, alignment: .leading)
            Text(connection.config.name).font(.callout).lineLimit(1)
            Spacer()
            Button {
                if connection.isFullyConnected {
                    state.portForwardManager.stopConnection(connection.id)
                } else if connection.portForwardStatus != .connecting && connection.proxyStatus != .connecting {
                    state.portForwardManager.startConnection(connection.id)
                }
            } label: {
                HStack(spacing: 3) {
                    if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: connection.isFullyConnected ? "stop.fill" : "play.fill")
                    }
                    Text(connection.isFullyConnected ? "Stop" : "Start")
                }
                .font(.caption)
                .foregroundStyle(connection.isFullyConnected ? .red : .green)
            }
            .buttonStyle(.bordered).controlSize(.small)
            .opacity(isHovered ? 1 : 0.6)
            .disabled(connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button { state.portForwardManager.restartConnection(connection.id) } label: { Label("Restart", systemImage: "arrow.clockwise") }
            Divider()
            Button { if let url = URL(string: "http://localhost:" + String(connection.effectivePort)) { NSWorkspace.shared.open(url) } } label: { Label("Open in Browser", systemImage: "globe.fill") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("http://localhost:" + String(connection.effectivePort), forType: .string) } label: { Label("Copy URL", systemImage: "document.on.clipboard") }
            Divider()
            Button(role: .destructive) { state.portForwardManager.removeConnection(connection.id) } label: { Label("Remove", systemImage: "trash") }
        }
    }
}
