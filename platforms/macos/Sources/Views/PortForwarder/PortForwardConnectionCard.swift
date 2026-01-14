import SwiftUI

struct PortForwardConnectionCard: View {
    let connection: PortForwardConnectionState
    var isSelected: Bool = false
    var onSelect: (() -> Void)?
    @Environment(AppState.self) private var appState
    @State private var isExpanded = false

    private var statusColor: Color {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return .red
        } else if connection.isFullyConnected {
            return .green
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return .orange
        } else {
            return .gray.opacity(0.4)
        }
    }

    private var statusText: String {
        if connection.portForwardStatus == .error || connection.proxyStatus == .error {
            return "Error"
        } else if connection.isFullyConnected {
            return "Connected"
        } else if connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting {
            return "Connecting..."
        } else {
            return "Disconnected"
        }
    }

    private var isConnecting: Bool {
        connection.portForwardStatus == .connecting || connection.proxyStatus == .connecting
    }

    @ViewBuilder
    private var inlineActionButton: some View {
        if isConnecting {
            Button {
                appState.portForwardManager.stopConnection(connection.id)
            } label: {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        } else if connection.isFullyConnected {
            Button {
                appState.portForwardManager.stopConnection(connection.id)
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Stop")
        } else {
            Button {
                appState.portForwardManager.startConnection(connection.id)
            } label: {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Start")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(connection.config.name)
                    .fontWeight(.medium)

                Text("\u{00B7}")
                    .foregroundStyle(.tertiary)

                Text("\(connection.config.namespace)/\(connection.config.service)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                // Port info
                Text(":" + String(connection.effectivePort))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Status badge
                Text(statusText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())

                // Inline action button
                inlineActionButton

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)

                Button {
                    appState.portForwardManager.removeConnection(connection.id)
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
            }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                PortForwardConnectionEditForm(connection: connection)
                    .padding(12)
            }
        }
        .background(isSelected ? Color.accentColor.opacity(0.1) : statusColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : statusColor.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
    }
}
