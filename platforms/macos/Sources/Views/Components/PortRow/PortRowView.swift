/**
 * PortRowView.swift
 * PortKiller
 *
 * Unified port row component that supports multiple display styles.
 * Replaces PortListRow, NestedPortListRow, MenuBarPortRow, MenuBarNestedPortRow.
 */

import SwiftUI

/// Style configuration for PortRowView
enum PortRowStyle {
    /// Full table view row with all columns
    case table
    /// Nested row within a process group (indented)
    case nested
    /// Compact row for menu bar
    case menuBar
    /// Minimal nested row for menu bar
    case menuBarNested
}

/// Configuration for kill confirmation behavior
enum KillConfirmationMode {
    /// No confirmation, kill immediately
    case immediate
    /// Show inline confirmation UI
    case inline(confirmingKill: Binding<String?>)
}

/// Unified port row view supporting multiple display styles
struct PortRowView: View {
    let port: PortInfo
    let style: PortRowStyle
    var killMode: KillConfirmationMode = .immediate
    var contextMenuOptions: PortContextMenuOptions = .full

    @Environment(AppState.self) private var appState
    @State private var isHovered = false
    @State private var isKilling = false

    var body: some View {
        content
            .background(rowBackground)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .contextMenu {
                PortContextMenu(port: port, options: contextMenuOptionsForStyle)
            }
    }

    // MARK: - Content by Style

    @ViewBuilder
    private var content: some View {
        switch style {
        case .table:
            tableRowContent
        case .nested:
            nestedRowContent
        case .menuBar:
            menuBarRowContent
        case .menuBarNested:
            menuBarNestedContent
        }
    }

    // MARK: - Table Row (Full)

    private var tableRowContent: some View {
        HStack(spacing: 0) {
            // Favorite
            FavoriteButton(portNumber: port.port)
                .frame(width: 40, alignment: .center)

            // Status indicator
            PortStatusIndicator(isActive: port.isActive)
                .padding(.trailing, 8)

            // Port
            PortNumberDisplay(port: port.port, isActive: port.isActive)
                .frame(width: 70, alignment: .leading)

            // Process
            PortProcessInfo(
                processName: port.processName,
                processType: port.processType,
                isActive: port.isActive
            )
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            // PID
            Text(port.isActive ? String(port.pid) : "-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            // Type
            PortTypeBadge(processType: port.processType, isActive: port.isActive)
                .frame(width: 100, alignment: .leading)

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
                WatchButton(portNumber: port.port)
                PortKillButton(port: port, onRemove: removeFromList)
            }
            .frame(width: 80)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Nested Row

    private var nestedRowContent: some View {
        HStack(spacing: 0) {
            // Indent + Status + Port
            HStack(spacing: 4) {
                Color.clear.frame(width: 20)
                PortStatusIndicator(isActive: port.isActive, size: 6)
                PortNumberDisplay(port: port.port, isActive: port.isActive)
            }
            .frame(width: 90, alignment: .leading)
            .padding(.leading, 24)

            // Tree connector
            Text("└─")
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)

            // Indicators
            PortStatusBadges(portNumber: port.port)
                .frame(width: 130, alignment: .leading)

            // PID placeholder
            Text("-")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            // Type
            if port.isActive {
                PortTypeBadge(
                    processType: port.processType,
                    isActive: port.isActive,
                    font: .caption2
                )
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
            PortRowActions(port: port, showFavorite: true, showWatch: true, showKill: true)
                .frame(width: 80)
                .opacity(isHovered ? 1 : 0)
                .padding(.trailing, 16)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Menu Bar Row

    private var menuBarRowContent: some View {
        HStack(spacing: 10) {
            // Status with glow
            Circle()
                .fill(isKilling ? .orange : .green)
                .frame(width: 6, height: 6)
                .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                .opacity(isKilling ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.3), value: isKilling)

            if case .inline(let confirmingKill) = killMode, confirmingKill.wrappedValue == port.id {
                menuBarConfirmContent(confirmingKill: confirmingKill)
            } else {
                menuBarNormalContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func menuBarConfirmContent(confirmingKill: Binding<String?>) -> some View {
        Text("Kill \(port.processName)?")
            .font(.callout)
            .lineLimit(1)
        Spacer()
        HStack(spacing: 4) {
            Button("Kill") {
                isKilling = true
                confirmingKill.wrappedValue = nil
                Task { await appState.killPort(port) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)

            Button("Cancel") {
                confirmingKill.wrappedValue = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var menuBarNormalContent: some View {
        Group {
            // Port + indicators
            HStack(spacing: 3) {
                if appState.isFavorite(port.port) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(port.displayPort)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .lineLimit(1)
                if appState.isWatching(port.port) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: 100, alignment: .leading)
            .opacity(isKilling ? 0.5 : 1)

            // Process name
            Text(port.processName)
                .font(.callout)
                .lineLimit(1)
                .opacity(isKilling ? 0.5 : 1)

            Spacer()

            // PID
            Text("PID \(String(port.pid))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(isKilling ? 0.5 : 1)

            // Kill button or loading
            if isKilling {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            } else if case .inline(let confirmingKill) = killMode {
                Button {
                    confirmingKill.wrappedValue = port.id
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
            }
        }
    }

    // MARK: - Menu Bar Nested

    private var menuBarNestedContent: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.clear).frame(width: 32)
            Text(port.displayPort)
                .font(.system(.callout, design: .monospaced))
                .frame(width: 60, alignment: .leading)
            Text("\(port.address) • \(port.displayPort)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var rowBackground: some View {
        Group {
            switch style {
            case .table:
                isHovered ? Color.primary.opacity(0.05) : Color.clear
            case .nested:
                isHovered ? Color.primary.opacity(0.03) : Color.clear
            case .menuBar:
                (isHovered || isConfirming) ? Color.primary.opacity(0.05) : Color.clear
            case .menuBarNested:
                Color.clear
            }
        }
    }

    private var isConfirming: Bool {
        if case .inline(let confirmingKill) = killMode {
            return confirmingKill.wrappedValue == port.id
        }
        return false
    }

    private var contextMenuOptionsForStyle: PortContextMenuOptions {
        switch style {
        case .table:
            return .full
        case .nested:
            return .nested
        case .menuBar:
            return .menuBar
        case .menuBarNested:
            return .minimal
        }
    }

    private func removeFromList() {
        if appState.isFavorite(port.port) {
            appState.favorites.remove(port.port)
        }
        if appState.isWatching(port.port) {
            appState.toggleWatch(port.port)
        }
    }
}
