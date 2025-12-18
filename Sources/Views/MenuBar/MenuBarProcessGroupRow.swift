import SwiftUI

struct MenuBarProcessGroupRow: View {
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
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                Circle().fill(isKilling ? .orange : .green).frame(width: 6, height: 6)
                    .shadow(color: (isKilling ? Color.orange : Color.green).opacity(0.5), radius: 3)
                    .opacity(isKilling ? 0.5 : 1).animation(.easeInOut(duration: 0.3), value: isKilling)
                HStack(spacing: 4) {
                    if group.ports.contains(where: { state.isFavorite($0.port) }) { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    Text(group.processName).font(.callout).fontWeight(.medium).lineLimit(1)
                    if group.ports.contains(where: { state.isWatching($0.port) }) { Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.blue) }
                }
                Spacer()
                Text("PID \(String(group.id))").font(.caption2).foregroundStyle(.secondary)
                if !(isHovered || showConfirm) {
                    Text("\(group.ports.count)").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 5).background(.tertiary.opacity(0.5)).clipShape(Capsule())
                } else if !showConfirm {
                    Button { showConfirm = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }.buttonStyle(.plain)
                }
                if showConfirm {
                    HStack(spacing: 4) {
                        Button { showConfirm = false; isKilling = true; onKillProcess() } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }.buttonStyle(.plain)
                        Button { showConfirm = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle()).onHover { isHovered = $0 }.onTapGesture { onToggleExpand() }
            if isExpanded { ForEach(group.ports) { port in MenuBarNestedPortRow(port: port, state: state) } }
        }
    }
}
