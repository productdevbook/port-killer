import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var state: AppState
    @State private var searchText = ""
    @State private var confirmingKillAll = false
    @State private var confirmingKillPort: UUID?
    @State private var hoveredPort: UUID?

    private var filteredPorts: [PortInfo] {
        let filtered = searchText.isEmpty ? state.ports : state.ports.filter {
            String($0.port).contains(searchText) || $0.processName.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { a, b in
            let aFav = state.isFavorite(a.port)
            let bFav = state.isFavorite(b.port)
            if aFav != bFav { return aFav }
            return a.port < b.port
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.quaternary)
                .cornerRadius(6)
                Text("\(filteredPorts.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.tertiary.opacity(0.3))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Port List
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filteredPorts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.green)
                            Text("No open ports")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredPorts) { port in
                            PortRow(port: port, state: state, isHovered: hoveredPort == port.id, confirmingKill: $confirmingKillPort)
                                .onHover { hoveredPort = $0 ? port.id : nil }
                        }
                    }
                }
            }
            .frame(maxHeight: 400)

            Divider()

            // Toolbar
            HStack(spacing: 16) {
                Button { Task { await state.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")
                .keyboardShortcut("r", modifiers: .command)

                if confirmingKillAll {
                    HStack(spacing: 4) {
                        Button("Kill All") {
                            Task { await state.killAll() }
                            confirmingKillAll = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        Button("Cancel") { confirmingKillAll = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    Button { confirmingKillAll = true } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.ports.isEmpty)
                    .help("Kill All")
                    .keyboardShortcut("k", modifiers: .command)
                }

                Spacer()

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .help("Settings")
                .keyboardShortcut(",", modifiers: .command)

                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .help("Quit")
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

// MARK: - Port Row
struct PortRow: View {
    let port: PortInfo
    @Bindable var state: AppState
    let isHovered: Bool
    @Binding var confirmingKill: UUID?
    @State private var isKilling = false

    private var isConfirming: Bool { confirmingKill == port.id }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isKilling ? .orange : .green)
                .frame(width: 8, height: 8)

            if isConfirming {
                Text("Kill \(port.processName)?")
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Button("Kill") {
                        isKilling = true
                        confirmingKill = nil
                        Task { await state.killPort(port) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                    Button("Cancel") { confirmingKill = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 3) {
                    if state.isFavorite(port.port) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(port.displayPort)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    if state.isWatching(port.port) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(width: 80, alignment: .leading)
                .opacity(isKilling ? 0.5 : 1)

                Text(port.processName)
                    .font(.callout)
                    .lineLimit(1)
                    .opacity(isKilling ? 0.5 : 1)

                Spacer()

                Text("PID \(port.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(isKilling ? 0.5 : 1)

                if isKilling {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.orange)
                } else {
                    Button { confirmingKill = port.id } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((isHovered || isConfirming) ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button { state.toggleFavorite(port.port) } label: {
                Label(state.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: state.isFavorite(port.port) ? "star.slash" : "star")
            }
            Divider()
            Button { state.toggleWatch(port.port) } label: {
                Label(state.isWatching(port.port) ? "Stop Watching" : "Watch Port",
                      systemImage: state.isWatching(port.port) ? "eye.slash" : "eye")
            }
        }
    }
}
