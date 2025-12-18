import SwiftUI

struct MenuBarNestedPortRow: View {
    let port: PortInfo
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.clear).frame(width: 32)
            Text(port.displayPort).font(.system(.callout, design: .monospaced)).frame(width: 60, alignment: .leading)
            Text("\(port.address) • \(port.displayPort)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
        .contextMenu {
            Button { state.toggleFavorite(port.port) } label: { Label(state.isFavorite(port.port) ? "Remove from Favorites" : "Add to Favorites", systemImage: state.isFavorite(port.port) ? "star.slash" : "star") }
            Divider()
            Button { state.toggleWatch(port.port) } label: { Label(state.isWatching(port.port) ? "Stop Watching" : "Watch Port", systemImage: state.isWatching(port.port) ? "eye.slash" : "eye") }
            Divider()
            Button { if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) } } label: { Label("Open in Browser", systemImage: "globe.fill") }
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string) } label: { Label("Copy URL", systemImage: "document.on.clipboard") }
        }
    }
}
