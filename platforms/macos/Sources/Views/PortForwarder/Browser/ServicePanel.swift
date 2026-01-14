import SwiftUI

struct ServicePanel: View {
    let services: [KubernetesService]
    let selectedService: KubernetesService?
    let state: KubernetesDiscoveryState
    let onSelect: (KubernetesService) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Services")
                    .font(.headline)
                Spacer()
                Text("\(services.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            if state == .loading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if state == .idle {
                VStack {
                    Spacer()
                    Text("Select a namespace")
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(services) { svc in
                            Button { onSelect(svc) } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(svc.name)
                                            .font(.system(.body, design: .monospaced))
                                        Text("\(svc.type) \u{00B7} \(svc.ports.count) ports")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedService?.id == svc.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
