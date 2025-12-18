/// SettingsComponents - Reusable UI components for settings
///
/// Provides consistent styling for settings sections:
/// - SettingsGroup: Container with icon and title
/// - SettingsRowContainer: Padding wrapper for rows
/// - SettingsToggleRow: Toggle with title and subtitle
/// - SettingsButtonRow: Button with icon and description
/// - SettingsLinkRow: External link with arrow indicator
/// - SettingsDivider: Indented divider line
///
/// - Note: All components follow macOS Big Sur+ design patterns.

import SwiftUI

// MARK: - Settings Group

/// Container for a section of related settings with icon and title
struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }

            content
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - Row Container

/// Wrapper that adds consistent padding to settings rows
struct SettingsRowContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
    }
}

// MARK: - Toggle Row

/// Toggle row with title and subtitle text
struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRowContainer {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
}

// MARK: - Button Row

/// Button row with icon, title, subtitle, and action
struct SettingsButtonRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContainer {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .fontWeight(.medium)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Link Row

/// External link row with icon, title, subtitle, and arrow indicator
struct SettingsLinkRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            SettingsRowContainer {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .fontWeight(.medium)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Divider

/// Indented divider for separating settings rows
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 50)
    }
}
