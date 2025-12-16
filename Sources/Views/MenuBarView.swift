import SwiftUI 

// MARK: - Process Group

struct ProcessGroup: Identifiable {
	let id: Int // Use PID as stable identifier
	let processName: String
	let ports: [PortInfo]
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var state: AppState
    @State private var searchText = ""
    @State private var confirmingKillAll = false
    @State private var confirmingKillPort: UUID?
    @State private var hoveredPort: UUID?
	@State private var expandedProcesses: Set<Int> = []
	@State private var useTreeView = UserDefaults.standard.bool(forKey: "useTreeView")
	
	private var groupedByProcess: [ProcessGroup] {
		let grouped = Dictionary(grouping: filteredPorts) { $0.pid }
		return grouped.map { pid, ports in
			ProcessGroup(
				id: pid,
				processName: ports.first?.processName ?? "Unknown",
				ports: ports.sorted { $0.port < $1.port }
			)
		}.sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
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
							Image(systemName: "checkmark.circle")
								.font(.largeTitle)
								.foregroundStyle(.green)
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
									}
								)
							}
					} else {
                        ForEach(filteredPorts) { port in
                            PortRow(port: port, state: state, confirmingKill: $confirmingKillPort)
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
				
				// View toggle button
				Button {
					useTreeView.toggle()
					UserDefaults.standard.set(useTreeView, forKey: "useTreeView")
				} label: {
					Image(systemName: useTreeView ? "list.bullet" : "list.bullet.indent")
				}
				.buttonStyle(.plain)
				.help(useTreeView ? "Show list view" : "Show tree view")
				.keyboardShortcut("t", modifiers: .command)
				
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}

// MARK: - Process Group Row

struct ProcessGroupRow: View {
	let group: ProcessGroup
	let isExpanded: Bool
	let onToggleExpand: () -> Void
	let onKillProcess: () -> Void
	
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
					.opacity(isKilling ? 0.3 : 1)
					.animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isKilling)
				
				// Process name with port count
				Text(group.processName)
					.font(.callout)
					.fontWeight(.medium)
				
				Spacer()
				
				// PID
				Text("PID \(group.id)")
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
					NestedPortRow(port: port)
				}
			}
		}
	}
}

// MARK: - Nested Port Row

struct NestedPortRow: View {
	let port: PortInfo
	
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
			
			Spacer()
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 6)
		.contentShape(Rectangle())
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
        }
    }
}
