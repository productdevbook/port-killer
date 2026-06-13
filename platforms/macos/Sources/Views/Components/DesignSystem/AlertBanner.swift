import SwiftUI

/// A tinted inline banner with a leading icon, title/subtitle, a top accent bar, and a
/// trailing action area. Generalizes DependencyWarningBanner and CloudflaredMissingBanner.
struct AlertBanner<Trailing: View>: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.Colors.statusWarning
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .textStyle(.sectionTitle)
                Text(message)
                    .textStyle(.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing
        }
        .padding(Spacing.lg)
        .background(tint.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(tint)
                .frame(height: 2),
            alignment: .top
        )
    }
}

extension AlertBanner where Trailing == EmptyView {
    init(icon: String, title: String, message: String, tint: Color = Theme.Colors.statusWarning) {
        self.init(icon: icon, title: title, message: message, tint: tint) { EmptyView() }
    }
}
