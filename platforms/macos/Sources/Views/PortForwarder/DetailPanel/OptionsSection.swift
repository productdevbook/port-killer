import SwiftUI

struct OptionsSection: View {
    @Binding var proxyEnabled: Bool
    @Binding var useDirectExec: Bool
    @Binding var autoReconnect: Bool
    @Binding var isEnabled: Bool
    @Binding var notifyOnConnect: Bool
    @Binding var notifyOnDisconnect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Options", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Toggle(isOn: $proxyEnabled) {
                    Label("Proxy", systemImage: "network")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if proxyEnabled {
                    Toggle(isOn: $useDirectExec) {
                        Label("Multi-conn", systemImage: "arrow.triangle.branch")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Enable multiple simultaneous connections")
                }

                Spacer()
            }

            HStack(spacing: 20) {
                Toggle(isOn: $autoReconnect) {
                    Label("Auto Reconnect", systemImage: "arrow.clockwise")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $isEnabled) {
                    Label("Enabled", systemImage: "power")
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .font(.callout)

            HStack(spacing: 20) {
                Toggle(isOn: $notifyOnConnect) {
                    Label("Notify on Connect", systemImage: "bell")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $notifyOnDisconnect) {
                    Label("Notify on Disconnect", systemImage: "bell.slash")
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .font(.callout)
        }
    }
}
