import SwiftUI
import Defaults

struct NotificationsSettingsSection: View {
    @Default(.notifyProcessTypes) private var enabledTypes

    var body: some View {
        SettingsGroup("Port Notifications", icon: "bell.fill") {
            VStack(spacing: 0) {
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify on new ports by process type")
                            .fontWeight(.medium)
                        Text("Get notified when a port opens for selected process types")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(ProcessType.allCases) { type in
                    SettingsDivider()
                    processTypeToggle(type)
                }
            }
        }
    }

    private func processTypeToggle(_ type: ProcessType) -> some View {
        SettingsRowContainer {
            Toggle(isOn: Binding(
                get: { enabledTypes.contains(type.rawValue) },
                set: { enabled in
                    if enabled {
                        Defaults[.notifyProcessTypes].insert(type.rawValue)
                    } else {
                        Defaults[.notifyProcessTypes].remove(type.rawValue)
                    }
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: type.icon)
                        .foregroundStyle(type.color)
                        .frame(width: 20)
                    Text(type.rawValue)
                }
            }
        }
    }
}
