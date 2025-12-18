import SwiftUI

struct PortMappingSection: View {
    @Binding var localPort: String
    @Binding var remotePort: String
    @Binding var proxyPort: String
    let proxyEnabled: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Port Mapping", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Port flow visualization - centered
            HStack(alignment: .bottom, spacing: 8) {
                // Proxy port (if enabled)
                if proxyEnabled {
                    VStack(spacing: 4) {
                        Text("Proxy")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        TextField("port", text: $proxyPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.center)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.tertiary)
                        .frame(height: 22)
                }

                // Local port
                VStack(spacing: 4) {
                    Text("Local")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("port", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.center)
                }

                Image(systemName: "arrow.right")
                    .foregroundStyle(.blue)
                    .frame(height: 22)

                // Kubernetes icon
                Image(systemName: "cloud")
                    .foregroundStyle(.blue)
                    .font(.title3)
                    .frame(height: 22)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.blue)
                    .frame(height: 22)

                // Remote port
                VStack(spacing: 4) {
                    Text("Remote")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("port", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.center)
                }
            }
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity)
        }
    }
}
