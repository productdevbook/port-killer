import SwiftUI

/// Small globe icon next to a port number, signalling that the port is exposed
/// via a running named Cloudflare tunnel. Full hostname list lives in
/// `PortDetailView` — keeping the list compact.
///
/// Tooltip and context menu surface the hostnames inline for quick access.
struct TunnelExposureBadge: View {
    let port: Int
    var compact: Bool = false

    @Environment(AppState.self) private var appState

    private var exposures: [PortExposure] {
        appState.namedTunnelManager.exposures(for: port)
    }

    var body: some View {
        if exposures.isEmpty {
            EmptyView()
        } else {
            badge
        }
    }

    private var badge: some View {
        Button {
            if let first = exposures.first {
                open(first.publicURL)
            }
        } label: {
            Image(systemName: "globe")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .contextMenu {
            ForEach(exposures, id: \.publicURL) { exposure in
                Button {
                    open(exposure.publicURL)
                } label: { Label(exposure.publicURL, systemImage: "globe") }
            }
            Divider()
            ForEach(exposures, id: \.publicURL) { exposure in
                Button {
                    ClipboardService.copy(exposure.publicURL)
                } label: { Label("Copy \(exposure.publicURL)", systemImage: "doc.on.doc") }
            }
        }
    }

    private var tooltip: String {
        if exposures.count == 1, let one = exposures.first {
            return "Exposed via \(one.tunnelName): \(one.publicURL)"
        }
        let list = exposures.map { $0.publicURL }.joined(separator: ", ")
        return "\(exposures.count) routes: \(list)"
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
