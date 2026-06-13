import SwiftUI

/// An SF Symbol inside a tinted circle, used as a header glyph. Consolidates the
/// `ZStack { Circle().fill(color.opacity(0.2)); Image(systemName:).foregroundStyle(color) }`
/// pattern in detail panels and section headers.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = Sizing.iconBadge

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.4))
                .foregroundStyle(color)
        }
    }
}
