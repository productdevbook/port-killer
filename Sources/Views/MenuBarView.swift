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
        .frame(width: 450) // Increased width for better spacing
    }
}

// MARK: - Port Row
struct PortRow: View {
    let port: PortInfo
    @Bindable var state: AppState
    let isHovered: Bool
    @Binding var confirmingKill: UUID?
    @State private var isKilling = false
    @State private var isExpanded = false

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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if state.isFavorite(port.port) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text(port.displayPort)
                            .font(.system(.callout, design: .monospaced))
                            .fontWeight(.semibold)
                        if state.isWatching(port.port) {
                            Image(systemName: "eye.fill")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text("PID \(port.pid)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 90, alignment: .leading)
                .opacity(isKilling ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 6) {
                    // Process name and expand button
                    HStack(spacing: 8) {
                        Text(port.processName)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .opacity(isKilling ? 0.5 : 1)
                        
                        Spacer()
                        
                        if let description = port.description, !description.text.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: categoryIcon(for: description.category))
                                        .font(.caption)
                                        .foregroundStyle(categoryColor(for: description.category))
                                    
                                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(isExpanded ? "Collapse description" : "Show description")
                        }
                    }
                    
                    // Description area
                    if let description = port.description {
                        if isExpanded {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: categoryIcon(for: description.category))
                                        .font(.caption)
                                        .foregroundStyle(categoryColor(for: description.category))
                                    
                                    Text(description.category.rawValue.capitalized)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                }
                                
                                Text(description.text)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(.quaternary.opacity(0.5))
                                    .cornerRadius(6)
                                    .opacity(isKilling ? 0.5 : 1)
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon(for: description.category))
                                    .font(.caption2)
                                    .foregroundStyle(categoryColor(for: description.category))
                                
                                Text(truncateDescription(description.text, maxWidth: 55))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .opacity(isKilling ? 0.5 : 1)
                                    .help(description.text)
                            }
                        }
                    }
                }

                Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    
    // Helper functions for category visualization
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
