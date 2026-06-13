import SwiftUI

/// 8pt-grid spacing scale. Replaces scattered magic numbers in `.padding`/`spacing:`.
enum Spacing {
    /// 2pt — hairline gaps inside tight stacks.
    static let xxs: CGFloat = 2
    /// 4pt — compact row vertical padding.
    static let xs: CGFloat = 4
    /// 6pt — tight.
    static let sm: CGFloat = 6
    /// 8pt — base unit (most common stack spacing / row vertical padding).
    static let md: CGFloat = 8
    /// 12pt — comfortable (cards, horizontal row padding).
    static let lg: CGFloat = 12
    /// 16pt — section spacing.
    static let xl: CGFloat = 16
    /// 24pt — page / large section spacing.
    static let xxl: CGFloat = 24
}

/// Corner-radius scale.
enum Radius {
    /// 6pt — text fields, small cards, inset areas.
    static let sm: CGFloat = 6
    /// 8pt — cards, badges, containers.
    static let md: CGFloat = 8
    /// 12pt — large panels.
    static let lg: CGFloat = 12
}

/// Common fixed sizes.
enum Sizing {
    /// Status indicator dot in compact rows (menu bar).
    static let statusDotSmall: CGFloat = 6
    /// Status indicator dot in tables/sidebar.
    static let statusDot: CGFloat = 8
    /// Icon-in-circle header badge.
    static let iconBadge: CGFloat = 48
}
