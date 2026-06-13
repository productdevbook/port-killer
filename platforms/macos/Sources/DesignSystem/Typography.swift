import SwiftUI

/// Named text styles. Replaces ad-hoc inline `.font(...)` combos with semantic roles
/// so type scale and weight stay consistent across the app.
///
/// Usage: `Text("…").textStyle(.rowTitle)`.
enum TextRole {
    /// Primary label in a list row.
    case rowTitle
    /// Secondary / supporting text in a row.
    case rowSubtitle
    /// Section heading.
    case sectionTitle
    /// Small uppercase-ish badge/pill label.
    case badge
    /// Technical metadata (PID, fd, addresses) — monospaced.
    case metadata
    /// A port number — monospaced, medium.
    case portNumber
    /// Smallest caption text.
    case footnote

    var font: Font {
        switch self {
        case .rowTitle: .callout.weight(.medium)
        case .rowSubtitle: .caption
        case .sectionTitle: .headline
        case .badge: .caption.weight(.medium)
        case .metadata: .system(.caption, design: .monospaced)
        case .portNumber: .system(.callout, design: .monospaced).weight(.medium)
        case .footnote: .caption2
        }
    }
}

extension View {
    /// Applies a named text style.
    func textStyle(_ role: TextRole) -> some View {
        font(role.font)
    }
}
