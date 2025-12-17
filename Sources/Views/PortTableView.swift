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
        case address = "Address"
        case user = "User"
        case actions = "Actions"
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
                        if useTreeView {
                            ForEach(groupedPorts) { group in
                                ProcessGroupListRow(
                                    group: group,
                                    isExpanded: expandedProcesses.contains(group.id),
                                    onToggleExpand: {
                                        if expandedProcesses.contains(group.id) {
                                            expandedProcesses.remove(group.id)
                                        } else {
                                            expandedProcesses.insert(group.id)
                                        }
                                    }
                                )
                                
                                if expandedProcesses.contains(group.id) {
                                    ForEach(group.ports) { port in
                                        NestedPortListRow(port: port)
                                            .background(appState.selectedPortID == port.id ? Color.accentColor.opacity(0.2) : Color.clear)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                appState.selectedPortID = port.id
                                            }
                                    }
                                }
                            }
                        } else {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    useTreeView.toggle()
                } label: {
                    Label(useTreeView ? "List View" : "Tree View", systemImage: useTreeView ? "list.bullet" : "list.bullet.indent")
                }
                .help(useTreeView ? "Switch to List View" : "Switch to Tree View")
            }
        }
    }

    private var groupedPorts: [ProcessGroup] {
        let grouped = Dictionary(grouping: appState.filteredPorts) { $0.pid }
        return grouped.map { pid, ports in
            ProcessGroup(
                id: pid,
                processName: ports.first?.processName ?? "Unknown",
                ports: ports.sorted { $0.port < $1.port }
            )
        }.sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            // Favorite header (centered)
            Button {
                if sortOrder == .actions {
                    sortAscending.toggle()
                } else {
                    sortOrder = .actions
                    sortAscending = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("★")
                        .font(.caption.weight(.medium))
                    if sortOrder == .actions {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(sortOrder == .actions ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 40, alignment: .center)
            
            // Account for status indicator circle space
            Spacer()
                .frame(width: 16)
            headerButton("Port", .port, width: 70)
            // Process column (flexible)
            Button {
                if sortOrder == .process {
                    sortAscending.toggle()
                } else {
                    sortOrder = .process
                    sortAscending = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Process")
                        .font(.caption.weight(.medium))
                    if sortOrder == .process {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(sortOrder == .process ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            
            headerButton("PID", .pid, width: 70)
            headerButton("Type", .type, width: 100)
            headerButton("Address", .address, width: 80)
            headerButton("User", .user, width: 70)
            Spacer()
            Text("Actions")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 80)
        }
        .padding(.leading, 16)
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
            case .address:
                result = a.address.localizedCaseInsensitiveCompare(b.address) == .orderedAscending
            case .user:
                result = a.user.localizedCaseInsensitiveCompare(b.user) == .orderedAscending
            case .actions:
                // Sort by favorite/watched status
                let aIsFavorite = appState.isFavorite(a.port)
                let aIsWatching = appState.isWatching(a.port)
                let bIsFavorite = appState.isFavorite(b.port)
                let bIsWatching = appState.isWatching(b.port)
                
                // Priority: Favorite > Watching > Neither
                let aPriority = aIsFavorite ? 2 : (aIsWatching ? 1 : 0)
                let bPriority = bIsFavorite ? 2 : (bIsWatching ? 1 : 0)
                
                if aPriority != bPriority {
                    result = aPriority > bPriority
                } else {
                    // Same priority, sort by port number
                    result = a.port < b.port
                }
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
            // Favorite
            Button {
                appState.toggleFavorite(port.port)
            } label: {
                Image(systemName: appState.isFavorite(port.port) ? "star.fill" : "star")
                    .foregroundStyle(appState.isFavorite(port.port) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle favorite")
            .frame(width: 40, alignment: .center)

            // Status indicator
            Circle()
                .fill(port.isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .padding(.trailing, 8)

            // Port
            Text(String(port.port))
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
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
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            // PID
            Text(port.isActive ? String(port.pid) : "-")
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
            .frame(width: 80)
        }
        .padding(.leading, 16)
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
