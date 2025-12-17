/// MenuBarPortRow - Individual port row components for menu bar
///
/// Contains three row types:
/// - ProcessGroupRow: Collapsible header for grouped ports in tree view
/// - NestedPortRow: Individual port within an expanded process group
/// - PortRow: Standalone port row in list view
///
/// - Note: Each row includes context menus for common actions.
/// - Important: ProcessGroupRow handles killing all ports in a group.

import SwiftUI

// MARK: - Process Group Row

/// Collapsible row representing a process with multiple ports
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
            // Process header
            HStack(spacing: 10) {
                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Status indicator
                Circle()
                    .fill(isKilling ? .orange : .green)
                    .frame(width: 6, height: 6)
                    .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                    .opacity(isKilling ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.3), value: isKilling)

                // Process name with port count
                HStack(spacing: 4) {
                    if group.ports.contains(where: { state.isFavorite($0.port) }) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(group.processName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if group.ports.contains(where: { state.isWatching($0.port) }) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                Spacer()

                // PID
                Text("PID \(String(group.id))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !(isHovered || showConfirm) {
                    Text("\(group.ports.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .background(.tertiary.opacity(0.5))
                        .clipShape(Capsule())
                } else if !showConfirm {
                    Button {
                        showConfirm = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }

                if showConfirm {
                    HStack(spacing: 4) {
                        Button {
                            showConfirm = false
                            isKilling = true
                            onKillProcess()
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showConfirm = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                onToggleExpand()
            }

            // Expanded ports
            if isExpanded {
                ForEach(group.ports) { port in
                    NestedPortRow(port: port, state: state)
                }
            }
        }
    }
}

// MARK: - Nested Port Row

/// Individual port row within an expanded process group
struct NestedPortRow: View {
    let port: PortInfo
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            // Indent for nesting
            Rectangle()
                .fill(.clear)
                .frame(width: 32)

            // Port number
            Text(port.displayPort)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            // Address and protocol
            Text("\(port.address) • \(port.displayPort)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            Divider()
            Button {
                if let url = URL(string: "http://localhost:\(port.port)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "globe.fill")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
            } label: {
                Label("Copy URL", systemImage: "document.on.clipboard")
            }
        }
    }
}

// MARK: - List View Port Row

/// Standalone port row in list view mode
struct PortRow: View {
    let port: PortInfo
    @Bindable var state: AppState
    @Binding var confirmingKill: UUID?
    @State private var isKilling = false
    @State private var isHovered = false

    private var isConfirming: Bool { confirmingKill == port.id }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isKilling ? .orange : .green)
                .frame(width: 6, height: 6)
                .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                .opacity(isKilling ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.3), value: isKilling)

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
                        .lineLimit(1)
                    if state.isWatching(port.port) {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(width: 100, alignment: .leading)
                .opacity(isKilling ? 0.5 : 1)

                Text(port.processName)
                    .font(.callout)
                    .lineLimit(1)
                    .opacity(isKilling ? 0.5 : 1)

                Spacer()

                Text("PID \(String(port.pid))")
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
        .onHover { hovering in
            isHovered = hovering
        }
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
        }
    }
}
