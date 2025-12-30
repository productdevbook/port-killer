/// GeneralSettingsSection - General app preferences
///
/// Displays general settings including:
/// - Launch at login toggle
///
/// - Note: Uses LaunchAtLogin package for login item management.

import SwiftUI
import LaunchAtLogin
import Defaults

struct GeneralSettingsSection: View {
    @Default(.hideSystemProcesses) private var hideSystemProcesses
    
    var body: some View {
        SettingsGroup("General", icon: "gearshape.fill") {
            SettingsRowContainer {
                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .fontWeight(.medium)
                        Text("Start PortKiller when you log in")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
			
			SettingsToggleRow(
				title: "Hide System processes",
				subtitle: "Hide macOS processes from the process list",
				isOn: $hideSystemProcesses
			)
        }
    }
}
