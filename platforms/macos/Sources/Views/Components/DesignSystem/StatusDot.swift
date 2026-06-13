import SwiftUI

/// A small filled circle used as a status indicator. Replaces the many inline
/// `Circle().fill(...).frame(width:height:).shadow(...)` copies across rows.
struct StatusDot: View {
    let color: Color
    var size: CGFloat = Sizing.statusDot
    /// When true, adds a soft glow in the dot's color (used for "active" states).
    var glow: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: glow ? color.opacity(0.5) : .clear, radius: 3)
    }
}
