import SwiftUI

/// A colored capsule label. Consolidates the repeated
/// `Text(...).padding(...).background(color.opacity(0.15)).clipShape(Capsule())` pattern.
struct Badge: View {
    let text: String
    let color: Color
    var font: Font = TextRole.badge.font

    var body: some View {
        Text(text)
            .font(font)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xxs)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
