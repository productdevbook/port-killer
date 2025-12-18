import SwiftUI

struct MenuBarPortRow: View {
    let port: PortInfo
    @Bindable var state: AppState
    @Binding var confirmingKill: UUID?
    @State private var isKilling = false
    @State private var isHovered = false
    private var isConfirming: Bool { confirmingKill == port.id }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(isKilling ? .orange : .green).frame(width: 6, height: 6)
                .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                .opacity(isKilling ? 0.5 : 1).animation(.easeInOut(duration: 0.3), value: isKilling)
            if isConfirming {
                Text("Kill \(port.processName)?").font(.callout).lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Button("Kill") { isKilling = true; confirmingKill = nil; Task { await state.killPort(port) } }.buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                    Button("Cancel") { confirmingKill = nil }.buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                HStack(spacing: 3) {
                    if state.isFavorite(port.port) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(port.displayPort).font(.system(.body, design: .monospaced)).fontWeight(.medium).lineLimit(1)
                    if state.isWatching(port.port) { Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.blue) }
                }.frame(width: 100, alignment: .leading).opacity(isKilling ? 0.5 : 1)
                Text(port.processName).font(.callout).lineLimit(1).opacity(isKilling ? 0.5 : 1)
                Spacer()
                Text("PID \(String(port.pid))").font(.caption).foregroundStyle(.secondary).opacity(isKilling ? 0.5 : 1)
                if isKilling { Image(systemName: "hourglass").foregroundStyle(.orange) }
                else { Button { confirmingKill = port.id } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain).opacity(isHovered ? 1 : 0) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background((isHovered || isConfirming) ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle()).onHover { isHovered = $0 }
        .contextMenu {
            Button { state.toggleFavorite(port.port) } label: { Label(state.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites", systemImage: state.isFavorite(port.port) ? "star.slash" : "star") }
            Divider()
            Button { state.toggleWatch(port.port) } label: { Label(state.isWatching(port.port) ? "Stop Watching" : "Watch Port", systemImage: state.isWatching(port.port) ? "eye.slash" : "eye") }
            Divider()
            Button { if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) } } label: { Label("Open in Browser", systemImage: "globe.fill") }.keyboardShortcut("o", modifiers: .command)
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string) } label: { Label("Copy URL", systemImage: "document.on.clipboard") }

            // Tunnel section
            if port.isActive {
                Divider()
                if state.tunnelManager.isCloudflaredInstalled {
                    if let tunnel = state.tunnelManager.tunnelState(for: port.port) {
                        if tunnel.status == .active, let url = tunnel.tunnelURL {
                            Button { ClipboardService.copy(url) } label: { Label("Copy Tunnel URL", systemImage: "doc.on.doc") }
                            Button { if let tunnelURL = URL(string: url) { NSWorkspace.shared.open(tunnelURL) } } label: { Label("Open Tunnel URL", systemImage: "globe") }
                        }
                        Button { state.tunnelManager.stopTunnel(for: port.port) } label: { Label("Stop Tunnel", systemImage: "icloud.slash") }
                    } else {
                        Button { state.tunnelManager.startTunnel(for: port.port, portInfoId: port.id) } label: { Label("Share via Tunnel", systemImage: "cloud.fill") }
                    }
                } else {
                    Button { ClipboardService.copy("brew install cloudflared") } label: { Label("Copy: brew install cloudflared", systemImage: "doc.on.doc") }
                }
            }
        }
    }
}
