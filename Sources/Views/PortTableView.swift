import SwiftUI
import Defaults

struct PortTableView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .port
    @State private var sortAscending = true
    @Default(.useTreeView) private var useTreeView
    @State private var expandedProcesses: Set<Int> = []


    enum SortOrder: String, CaseIterable {
        case port = "Port"
        case process = "Process"
        case pid = "PID"
        case type = "Type"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerRow

            Divider()

            // Port List
            if appState.filteredPorts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedPorts) { port in
                            PortListRow(port: port)
                                .background(appState.selectedPortID == port.id ? Color.accentColor.opacity(0.2) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedPortID = port.id
                                }
                        }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerButton("Port", .port, width: 70)
            headerButton("Process", .process, width: 150)
            headerButton("PID", .pid, width: 70)
            headerButton("Type", .type, width: 100)
            Text("Address")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text("User")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text("Actions")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func headerButton(_ title: String, _ order: SortOrder, width: CGFloat) -> some View {
        Button {
            if sortOrder == order {
                sortAscending.toggle()
            } else {
                sortOrder = order
                sortAscending = true
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                if sortOrder == order {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .foregroundStyle(sortOrder == order ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: width, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Ports", systemImage: "network.slash")
        } description: {
            Text("No listening ports found")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sortedPorts: [PortInfo] {
        let ports = appState.filteredPorts
        return ports.sorted { a, b in
            let result: Bool
            switch sortOrder {
            case .port:
                result = a.port < b.port
            case .process:
                result = a.processName.localizedCaseInsensitiveCompare(b.processName) == .orderedAscending
            case .pid:
                result = a.pid < b.pid
            case .type:
                result = a.processType.rawValue < b.processType.rawValue
            }
            return sortAscending ? result : !result
        }
    }
}

// MARK: - Port List Row

struct PortListRow: View {
    let port: PortInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Status indicator
            Circle()
                .fill(port.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.trailing, 8)

            // Port
            HStack(spacing: 4) {
                if appState.isFavorite(port.port) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(String(port.port))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                if appState.isWatching(port.port) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 70, alignment: .leading)
            .opacity(port.isActive ? 1 : 0.6)

            // Process
            HStack(spacing: 6) {
                Image(systemName: port.processType.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(port.processName)
                    .lineLimit(1)
                    .foregroundStyle(port.isActive ? .primary : .secondary)
            }
            .frame(width: 150, alignment: .leading)

            // PID
            Text(port.isActive ? "\(port.pid)" : "-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Type
            if port.isActive {
                Text(port.processType.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            } else {
                Text("Inactive")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
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
                .help("Toggle favorite")

                Button {
                    appState.toggleWatch(port.port)
                } label: {
                    Image(systemName: appState.isWatching(port.port) ? "eye.fill" : "eye")
                        .foregroundStyle(appState.isWatching(port.port) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle watch")

                if port.isActive {
                    Button {
                        Task {
                            await appState.killPort(port)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Kill process (Delete)")
                } else {
                    Button {
                        // Remove from favorites/watched
                        if appState.isFavorite(port.port) {
                            appState.favorites.remove(port.port)
                        }
                        if appState.isWatching(port.port) {
                            appState.toggleWatch(port.port)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from list")
                }
            }
            .frame(width: 100)
        }
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                appState.toggleFavorite(port.port)
            } label: {
                Label(
                    appState.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: appState.isFavorite(port.port) ? "star.slash" : "star"
                )
            }

            Button {
                appState.toggleWatch(port.port)
            } label: {
                Label(
                    appState.isWatching(port.port) ? "Stop Watching" : "Watch Port",
                    systemImage: appState.isWatching(port.port) ? "eye.slash" : "eye"
                )
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(port.port), forType: .string)
            } label: {
                Label("Copy Port Number", systemImage: "doc.on.doc")
            }

            if port.isActive {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(port.command, forType: .string)
                } label: {
                    Label("Copy Command", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    Task {
                        await appState.killPort(port)
                    }
                } label: {
                    Label("Kill Process", systemImage: "xmark.circle")
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
			
			Divider()
			Button {
				if let url = URL(string: "http://localhost:\(port.port)") {
					NSWorkspace.shared.open(url)
				}
			} label: {
				Label("Open in Browser",systemImage: "globe.fill")
			}
			.keyboardShortcut("o", modifiers: .command)
			
			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
			} label: {
				Label("Copy URL",systemImage: "document.on.clipboard")
			}
        }
    }

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
