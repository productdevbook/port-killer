import SwiftUI

/// A rounded container with a fill and a hairline border. Consolidates the repeated
/// `RoundedRectangle(cornerRadius:).fill(...)` + `.strokeBorder(...)` card pattern.
struct Card<Content: View>: View {
    var background: Color = Theme.Colors.surfaceCard
    var border: Color = Theme.Colors.border
    var cornerRadius: CGFloat = Radius.md
    var padding: CGFloat = Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }
}
