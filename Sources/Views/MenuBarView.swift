import SwiftUI

struct MenuBarView: View {
    @Bindable var manager: PortManager
    @State private var hoveredPort: UUID?
    @State private var searchText = ""

    private func appIcon() -> NSImage {
        if let url = Bundle.module.url(forResource: "ToolbarIcon@2x", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "network", accessibilityDescription: nil) ?? NSImage()
    }

    private var filteredPorts: [PortInfo] {
        if searchText.isEmpty {
            return manager.ports
        }
        return manager.ports.filter {
            String($0.port).contains(searchText) ||
            $0.processName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            portsList
            Divider()
            actionsBar
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(nsImage: appIcon())
                .resizable()
                .frame(width: 18, height: 18)
            Text("PortKiller")
                .font(.headline)

            Spacer()

            Button {
                Task { await manager.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(manager.isScanning ? 360 : 0))
                    .animation(manager.isScanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: manager.isScanning)
            }
            .buttonStyle(.plain)
            .disabled(manager.isScanning)
            .help("Refresh")

            Text("\(manager.ports.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.tertiary.opacity(0.3))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search port or process...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Ports List

    private var portsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredPorts.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredPorts) { port in
                        PortRow(
                            port: port,
                            isHovered: hoveredPort == port.id,
                            onKill: {
                                Task { await manager.killPort(port) }
                            }
                        )
                        .onHover { hovering in
                            hoveredPort = hovering ? port.id : nil
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("No open ports")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions Bar

    private var actionsBar: some View {
        HStack(spacing: 12) {
            ActionButton(
                title: "Refresh",
                icon: "arrow.clockwise",
                action: { Task { await manager.refresh() } }
            )

            ActionButton(
                title: "Kill All",
                icon: "xmark.circle",
                isDestructive: true,
                action: { Task { await manager.killAll() } }
            )
            .disabled(manager.ports.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Port Row

struct PortRow: View {
    let port: PortInfo
    let isHovered: Bool
    let onKill: () -> Void

    @State private var isKilling = false
    @State private var showConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(isKilling ? .orange : .green)
                .frame(width: 8, height: 8)
                .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                .opacity(isKilling ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true), value: isKilling)

            // Port number
            Text(port.displayPort)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
                .opacity(isKilling ? 0.5 : 1)

            // Process name
            Text(port.processName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(isKilling ? 0.5 : 1)

            Spacer()

            // PID
            Text("PID \(port.pid)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(isKilling ? 0.5 : 1)

            // Kill button (visible on hover)
            if showConfirm {
                HStack(spacing: 4) {
                    Button {
                        showConfirm = false
                        isKilling = true
                        onKill()
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
            } else if isKilling {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.callout)
            .foregroundStyle(isDestructive ? .red : .primary)
        }
        .buttonStyle(.plain)
    }
}
