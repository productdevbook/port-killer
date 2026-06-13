import SwiftUI

/// PortKiller's brand identity — the single source of truth for the app's signature
/// colors. Derived from the app icon (a red plug with a yellow "kill" cross).
///
/// Use these for brand moments (onboarding, headers, primary accents), not for
/// semantic status — those live in `Theme.Colors`.
enum Brand {
    /// Primary brand red — top of the icon gradient.
    static let primary = Color(red: 1.0, green: 0.42, blue: 0.42)        // #FF6B6B

    /// Deep brand red — bottom of the icon gradient.
    static let primaryDeep = Color(red: 0.788, green: 0.165, blue: 0.165) // #C92A2A

    /// Accent yellow — the "kill cross" highlight.
    static let accent = Color(red: 1.0, green: 0.878, blue: 0.4)          // #FFE066

    /// The signature diagonal brand gradient (matches the icon background).
    static let gradient = LinearGradient(
        colors: [primary, primaryDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
