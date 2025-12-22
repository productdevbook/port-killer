/// ProcessGroupRow - Collapsible process group row for tree view
///
/// Displays a process group header with:
/// - Expand/collapse chevron
/// - Status indicator (active/killing)
/// - Process name with PID
/// - Port count badge
/// - Kill all ports button
///
/// - Note: Used in tree view to group multiple ports under one process.
/// - Important: Handles killing all ports in the group.

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
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 70, alignment: .leading)
            .padding(.leading, 24)

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
                        for port in group.ports {
                            appState.killPort(port)
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
        .onTapGesture {
            onToggleExpand()
        }
    }
}
