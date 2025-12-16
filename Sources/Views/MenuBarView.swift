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
    @State private var showInfoPopover = false

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

                HStack(spacing: 4) {
                    Text(port.processName)
                        .font(.callout)
                        .lineLimit(1)
                        .opacity(isKilling ? 0.5 : 1)
                    
                    // Info icon button - only show if there's description info
                    if let description = port.description, !description.text.isEmpty {
                        Button {
                            showInfoPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Show port information")
                        .popover(isPresented: $showInfoPopover, arrowEdge: .trailing) {
                            PortInfoPopover(port: port, isPresented: $showInfoPopover)
                        }
                    }
                }

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

// MARK: - Port Info Popover
struct PortInfoPopover: View {
    let port: PortInfo
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(port.processName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 6) {
                        Text("Port \(port.displayPort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        
                        Text("PID \(port.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let description = port.description {
                        // Category badge
                        HStack(spacing: 8) {
                            Image(systemName: categoryIcon(for: description.category))
                                .font(.title3)
                                .foregroundStyle(categoryColor(for: description.category))
                            
                            Text(description.category.rawValue.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(categoryColor(for: description.category))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(categoryColor(for: description.category).opacity(0.1))
                        .cornerRadius(8)
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            Text(description.text)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            
                            Text("No information available")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 350)
    }
    
    private func categoryIcon(for category: ProcessCategory) -> String {
        switch category {
        case .development:
            return "hammer.fill"
        case .database:
            return "cylinder.fill"
        case .webServer:
            return "globe"
        case .system:
            return "gearshape.fill"
        case .other:
            return "app.fill"
        }
    }
    
    private func categoryColor(for category: ProcessCategory) -> Color {
        switch category {
        case .development:
            return .blue
        case .database:
            return .green
        case .webServer:
            return .orange
        case .system:
            return .purple
        case .other:
            return .gray
        }
    }
}
