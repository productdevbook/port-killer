/**
 * PortRowComponents.swift
 * PortKiller
 *
 * Composable building blocks for port row displays.
 * These components can be combined to create different row layouts.
 */

import SwiftUI

// MARK: - Status Indicator

/// Displays active/inactive status as a colored circle
struct PortStatusIndicator: View {
    let isActive: Bool
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray)
            .frame(width: size, height: size)
    }
}

// MARK: - Port Number Display

/// Displays port number in monospaced font with optional custom label
struct PortNumberDisplay: View {
    let port: Int
    let isActive: Bool
    var font: Font = .system(.body, design: .monospaced)
    var fontWeight: Font.Weight = .medium
    var showLabel: Bool = true

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            Text(String(port))
                .font(font)
                .fontWeight(fontWeight)
                .opacity(isActive ? 1 : 0.6)

            if showLabel, let label = appState.portLabel(for: port) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Favorite/Watch Indicators

/// Shows favorite and watch status as small icons (read-only indicators)
struct PortStatusBadges: View {
    let portNumber: Int
    var fontSize: Font = .caption2

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 4) {
            if appState.isFavorite(portNumber) {
                Image(systemName: "star.fill")
                    .font(fontSize)
                    .foregroundStyle(.yellow)
            }
            if appState.isWatching(portNumber) {
                Image(systemName: "eye.fill")
                    .font(fontSize)
                    .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Process Info

/// Displays process name with type icon
struct PortProcessInfo: View {
    let processName: String
    let processType: ProcessType
    let isActive: Bool
    var showIcon: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if showIcon {
                Image(systemName: processType.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(processName)
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}

// MARK: - Type Badge

/// Displays process type as a colored capsule badge
struct PortTypeBadge: View {
    let processType: ProcessType
    let isActive: Bool
    var font: Font = .caption
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 2

    var body: some View {
        if isActive {
            Text(processType.rawValue)
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(processType.color.opacity(0.15))
                .foregroundStyle(processType.color)
                .clipShape(Capsule())
        } else {
            Text("Inactive")
                .font(font)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Color.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Kill Button

/// Kill/Remove button for ports
struct PortKillButton: View {
    let port: PortInfo
    var onRemove: (() -> Void)?

    @Environment(AppState.self) private var appState

    var body: some View {
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
            .help("Kill process")
        } else if let onRemove {
            Button {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove from list")
        }
    }
}

// MARK: - Actions Group

/// Combined action buttons for port rows
struct PortRowActions: View {
    let port: PortInfo
    var showFavorite: Bool = true
    var showWatch: Bool = true
    var showKill: Bool = true
    var onRemove: (() -> Void)?

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            if showFavorite {
                FavoriteButton(portNumber: port.port)
            }
            if showWatch {
                WatchButton(portNumber: port.port)
            }
            if showKill {
                PortKillButton(port: port, onRemove: onRemove)
            }
        }
    }
}
