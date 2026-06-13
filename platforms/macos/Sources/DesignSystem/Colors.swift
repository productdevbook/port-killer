import SwiftUI

/// Semantic color tokens. Views should reference these roles rather than raw
/// `.green`/`.red`/`Color(nsColor:)` literals so the palette can change in one place.
///
/// Process-type colors stay in `ProcessType+Color`, and tunnel-status colors in
/// `TunnelStatus+UI`; both already map onto the same underlying palette as below.
enum Theme {
    enum Colors {
        // MARK: Status

        /// Active / running / connected / success.
        static let statusSuccess = Color.green
        /// Error / failed / denied.
        static let statusError = Color.red
        /// Transitional or warning: starting / stopping / connecting.
        static let statusWarning = Color.orange
        /// Idle / stopped / inactive.
        static let statusIdle = Color.secondary.opacity(0.3)

        // MARK: Roles

        /// Destructive actions (kill, remove).
        static let danger = Color.red
        /// Favorite / highlight.
        static let favorite = Color.yellow
        /// Links and interactive URLs.
        static let link = Color.blue

        // MARK: Surfaces (NSColor bridges, centralized here)

        /// Background for cards and elevated containers.
        static let surfaceCard = Color(nsColor: .controlBackgroundColor)
        /// Inset text fields / log areas.
        static let surfaceField = Color(nsColor: .textBackgroundColor)
        /// Window chrome background.
        static let surfaceWindow = Color(nsColor: .windowBackgroundColor)
        /// Hairline borders and dividers.
        static let border = Color(nsColor: .separatorColor)

        // MARK: Interaction overlays

        /// Subtle hover tint over a row/card.
        static let hover = Color.primary.opacity(0.05)
        /// Selected-row tint.
        static let selected = Color.primary.opacity(0.1)
    }
}
