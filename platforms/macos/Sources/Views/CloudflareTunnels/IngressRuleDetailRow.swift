import SwiftUI

/// One ingress rule shown in the named-tunnel detail pane: public URL → service,
/// with open-in-browser and copy actions.
struct IngressRuleDetailRow: View {
    let rule: CloudflareTunnelIngressRule

    var body: some View {
        HStack(spacing: 10) {
            if let publicURL = rule.publicURL {
                Button {
                    if let url = URL(string: publicURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(publicURL)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.blue)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("(fallback)")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text(rule.service)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if let publicURL = rule.publicURL {
                Button {
                    ClipboardService.copy(publicURL)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy URL")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
