import SwiftUI

struct ProcessGroupListRow: View {
    let group: ProcessGroup
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var showConfirm = false
    @State private var isKilling = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Indent/Expand toggle (aligned with Port column of header)
            HStack(spacing: 0) {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 70, alignment: .leading)
            .padding(.leading, 24) // Match header padding
            
            // Process Name (aligned with Process column of header)
            HStack(spacing: 6) {
                // Status indicator
                Circle()
                    .fill(isKilling ? .orange : .green)
                    .frame(width: 8, height: 8)
                    .opacity(isKilling ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isKilling)
                
                Text(group.processName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
            }
            .frame(width: 150, alignment: .leading)
            
            // PID (aligned with PID column of header)
            Text("\(group.id)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            
            // Port Count Badge (aligned with Type column of header effectively)
            if !showConfirm {
                Text("\(group.ports.count) ports")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            } else {
                 Spacer().frame(width: 100)
            }

            Spacer()
            
            // Actions
            if showConfirm {
                HStack(spacing: 4) {
                    Button {
                        showConfirm = false
                        isKilling = true
                        Task {
                            for port in group.ports {
                                await appState.killPort(port)
                            }
                        }
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
                .frame(width: 80)
                .padding(.trailing, 16)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Kill Process Tree")
                .frame(width: 80)
                .padding(.trailing, 16)
            }
        }
        .padding(.vertical, 6)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct NestedPortListRow: View {
    let port: PortInfo
    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Indent spacing (aligned with Port column)
            HStack(spacing: 4) {
                 Color.clear.frame(width: 20) // Indent
                 
                 // Status indicator
                 Circle()
                    .fill(port.isActive ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                 
                 Text(String(port.port))
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .frame(width: 70 + 20, alignment: .leading) // Include indent in width calculation conceptually or add to it.
            // Actually, let's just use fixed frames to align with header columns roughly
            // Header: Port (70), Process (150), PID (70), Type (100), Address (80), User (70)
            
            .padding(.leading, 24) // Match header padding
            
            
            // Process (Empty for nested, or maybe protocol?)
            // Let's put something useful here or leave blank
            Text("└─")
                 .foregroundStyle(.tertiary)
                 .frame(width: 20, alignment: .trailing)
            
            HStack(spacing: 4) {
                if appState.isFavorite(port.port) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                if appState.isWatching(port.port) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 130, alignment: .leading)
            
            
            // PID (Already shown in group, so maybe dash or blank)
            Text("-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
            
            // Type
            if port.isActive {
                Text(port.processType.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.15))
                    .foregroundStyle(typeColor)
                    .clipShape(Capsule())
                    .frame(width: 100, alignment: .leading)
            } else {
                 Spacer().frame(width: 100)
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
                
                Button {
                    appState.toggleWatch(port.port)
                } label: {
                    Image(systemName: appState.isWatching(port.port) ? "eye.fill" : "eye")
                        .foregroundStyle(appState.isWatching(port.port) ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                
                if port.isActive {
                    Button {
                        Task { await appState.killPort(port) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 80)
            .opacity(isHovered ? 1 : 0)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button { appState.toggleFavorite(port.port) } label: {
                Label(appState.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: appState.isFavorite(port.port) ? "star.slash" : "star")
            }
            Button { appState.toggleWatch(port.port) } label: {
                Label(appState.isWatching(port.port) ? "Stop Watching" : "Watch Port",
                      systemImage: appState.isWatching(port.port) ? "eye.slash" : "eye")
            }
            Divider()
            Button {
                if let url = URL(string: "http://localhost:\(port.port)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Browser", systemImage: "globe")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
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
