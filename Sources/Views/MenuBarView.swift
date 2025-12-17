import SwiftUI
import Defaults

// MARK: - Process Group

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var state: AppState
    @State private var searchText = ""
    @State private var confirmingKillAll = false
    @State private var confirmingKillPort: UUID?
    @State private var hoveredPort: UUID?
	@State private var expandedProcesses: Set<Int> = []
	@State private var useTreeView = UserDefaults.standard.bool(forKey: "useTreeView")
	@State private var cachedGroups: [ProcessGroup] = []

	private var groupedByProcess: [ProcessGroup] { cachedGroups }

	private func updateGroupedByProcess() {
		let grouped = Dictionary(grouping: filteredPorts) { $0.pid }
		cachedGroups = grouped.map { pid, ports in
			ProcessGroup(
				id: pid,
				processName: ports.first?.processName ?? "Unknown",
				ports: ports.sorted { $0.port < $1.port }
			)
		}.sorted { a, b in
			// Check if groups have favorite or watched ports
			let aHasFavorite = a.ports.contains(where: { state.isFavorite($0.port) })
			let aHasWatched = a.ports.contains(where: { state.isWatching($0.port) })
			let bHasFavorite = b.ports.contains(where: { state.isFavorite($0.port) })
			let bHasWatched = b.ports.contains(where: { state.isWatching($0.port) })
			
			// Priority: Favorite > Watched > Neither
			let aPriority = aHasFavorite ? 2 : (aHasWatched ? 1 : 0)
			let bPriority = bHasFavorite ? 2 : (bHasWatched ? 1 : 0)
			
			if aPriority != bPriority {
				return aPriority > bPriority
			} else {
				// Same priority, sort alphabetically by process name
				return a.processName.localizedCaseInsensitiveCompare(b.processName) == .orderedAscending
			}
		}
	}
	
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
                            Image(systemName: "network.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No open ports")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if useTreeView {
                        ForEach(groupedByProcess) { group in
                            ProcessGroupRow(
                                group: group,
                                isExpanded: expandedProcesses.contains(group.id),
                                onToggleExpand: {
                                    if expandedProcesses.contains(group.id) {
                                        expandedProcesses.remove(group.id)
                                    } else {
                                        expandedProcesses.insert(group.id)
                                    }
                                },
                                onKillProcess: {
                                    for port in group.ports {
                                        Task { await state.killPort(port) }
                                    }
                                },
                                state: state
                            )
                        }
                    } else {
                        ForEach(filteredPorts) { port in
                            PortRow(port: port, state: state, confirmingKill: $confirmingKillPort)
                        }
                    }
                }
            }
            .frame(height: 400)

            Divider()

            // Menu Items
            VStack(spacing: 0) {
                MenuItemButton(title: "Refresh", icon: "arrow.clockwise", shortcut: "R") {
                    Task { await state.refresh() }
                }

                MenuItemButton(
                    title: useTreeView ? "List View" : "Tree View",
                    icon: useTreeView ? "list.bullet" : "list.bullet.indent",
                    shortcut: "T"
                ) {
                    useTreeView.toggle()
                }

                Divider()
                    .padding(.vertical, 4)

                if confirmingKillAll {
                    HStack {
                        Text("Kill all \(state.ports.count) processes?")
                            .font(.callout)
                        Spacer()
                        Button("Kill") {
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                } else {
                    MenuItemButton(title: "Kill All", icon: "xmark.circle", shortcut: "K", isDestructive: true) {
                        confirmingKillAll = true
                    }
                    .disabled(state.ports.isEmpty)
                }

                Divider()
                    .padding(.vertical, 4)

                MenuItemButton(title: "Open PortKiller", icon: "macwindow", shortcut: "O") {
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        bringMainWindowToFront()
                    }
                }

                MenuItemButton(title: "Sponsors", icon: "heart.fill") {
                    state.selectedSidebarItem = .sponsors
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        bringMainWindowToFront()
                    }
                }

                MenuItemButton(title: "Settings...", icon: "gear", shortcut: ",") {
                    state.selectedSidebarItem = .settings
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        bringMainWindowToFront()
                    }
                }

                MenuItemButton(title: "Quit PortKiller", icon: "power", shortcut: "Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 340)
        .onAppear { updateGroupedByProcess() }
        .onChange(of: state.ports) { _, _ in updateGroupedByProcess() }
        .onChange(of: searchText) { _, _ in updateGroupedByProcess() }
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
			// Process header
			HStack(spacing: 10) {
				// Expand/collapse indicator
				Button(action: onToggleExpand) {
					Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				
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
				
				if !(isHovered || showConfirm){
					Text("\(group.ports.count)")
						.font(.caption2)
						.foregroundStyle(.secondary)
						.padding(.horizontal, 5)
						//.padding(.vertical, 5)
						.background(.tertiary.opacity(0.5))
						.clipShape(Capsule())
				} else if !(showConfirm) {
					Button {
						showConfirm = true
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.red)
					}
					.buttonStyle(.plain)
					//.opacity(isHovered ? 1 : 0)
				}
				
				if showConfirm { // Kill process button (visible on hover)
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
				Label("Open in Browser",systemImage: "globe.fill")
			}
			
			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
			} label: {
				Label("Copy URL",systemImage: "document.on.clipboard")
			}
		}
	}
}
	
// MARK: - List View Port Row

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
}


// MARK: - Helper Functions

@MainActor
private func bringMainWindowToFront() {
    // For menu bar apps, we need to set activation policy to regular temporarily
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Find the main window (not menu bar extra)
    for window in NSApp.windows {
        // Skip menu bar extra windows
        if window.level == .popUpMenu || window.level == .statusBar {
            continue
        }
        if window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
    }
}

// MARK: - Menu Item Button

struct MenuItemButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Text(title)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
                if let shortcut = shortcut {
                    Text("⌘\(shortcut)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor : Color.clear)
            .foregroundStyle(isHovered ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
