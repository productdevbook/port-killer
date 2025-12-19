/// AdvancedSettingsSection - Advanced app preferences
///
/// Displays advanced settings including:
/// - Backend information (Rust-powered)
///
/// - Note: These settings are for power users and developers.

import SwiftUI

struct AdvancedSettingsSection: View {
    var body: some View {
        SettingsGroup("Advanced", icon: "gearshape.2.fill") {
            SettingsRowContainer {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Backend")
                                .fontWeight(.medium)
                            Text("Rust")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange)
                                .clipShape(Capsule())
                        }
                        Text("Port scanning and process management powered by Rust")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
