import SwiftUI

// MARK: - Port Forward Connection Row

struct PortForwardRow: View {
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

// MARK: - Cloudflare Tunnel Row

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

// MARK: - Process Group Row

struct ProcessGroupRow: View {
    let group: ProcessGroup
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onKillProcess: () -> Void
    @Bindable var state: AppState
    @State private var showConfirm = false
    @State private var isHovered = false
    @State private var isKilling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                Circle().fill(isKilling ? .orange : .green).frame(width: 6, height: 6)
                    .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                    .opacity(isKilling ? 0.5 : 1).animation(.easeInOut(duration: 0.3), value: isKilling)
                HStack(spacing: 4) {
                    if group.ports.contains(where: { state.isFavorite($0.port) }) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(group.processName).font(.callout).fontWeight(.medium).lineLimit(1)
                    if group.ports.contains(where: { state.isWatching($0.port) }) { Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.blue) }
                }
                Spacer()
                Text("PID \(String(group.id))").font(.caption2).foregroundStyle(.secondary)
                if !(isHovered || showConfirm) {
                    Text("\(group.ports.count)").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 5).background(.tertiary.opacity(0.5)).clipShape(Capsule())
                } else if !showConfirm {
                    Button { showConfirm = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
                }
                if showConfirm {
                    HStack(spacing: 4) {
                        Button { showConfirm = false; isKilling = true; onKillProcess() } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }.buttonStyle(.plain)
                        Button { showConfirm = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle()).onHover { isHovered = $0 }.onTapGesture { onToggleExpand() }
            if isExpanded { ForEach(group.ports) { port in NestedPortRow(port: port, state: state) } }
        }
    }
}

// MARK: - Nested Port Row

struct NestedPortRow: View {
    let port: PortInfo
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.clear).frame(width: 32)
            Text(port.displayPort).font(.system(.callout, design: .monospaced)).frame(width: 60, alignment: .leading)
            Text("\(port.address) • \(port.displayPort)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
        .contextMenu {
            Button { state.toggleFavorite(port.port) } label: { Label(state.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites", systemImage: state.isFavorite(port.port) ? "star.slash" : "star") }
            Divider()
            Button { state.toggleWatch(port.port) } label: { Label(state.isWatching(port.port) ? "Stop Watching" : "Watch Port", systemImage: state.isWatching(port.port) ? "eye.slash" : "eye") }
            Divider()
            Button { if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) } } label: { Label("Open in Browser", systemImage: "globe.fill") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string) } label: { Label("Copy URL", systemImage: "document.on.clipboard") }
        }
    }
}

// MARK: - Port Row

struct PortRow: View {
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
