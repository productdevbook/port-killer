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
    @Default(.appLanguage) private var appLanguage
    @Default(.hideSystemProcesses) private var hideSystemProcesses
    @Default(.skipKillConfirmation) private var skipKillConfirmation

    var body: some View {
        SettingsGroup("General", icon: "gearshape.fill") {
            SettingsRowContainer {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Language")
                            .fontWeight(.medium)
                        Text("Choose display language for PortKiller")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Picker("", selection: $appLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }

            SettingsDivider()

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

            SettingsDivider()

            SettingsToggleRow(
                title: "Skip kill confirmation",
                subtitle: "Kill processes immediately without confirmation prompt",
                isOn: $skipKillConfirmation
            )
        }
    }
}
