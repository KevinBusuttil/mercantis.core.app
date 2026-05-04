import SwiftUI

/// Spacing tokens used by Mercantis Core UI components.
///
/// These tokens centralize the inset/padding values so that workspace
/// headers, cards, and forms can share a consistent rhythm. Token names
/// follow a small/medium/large scale; existing call-sites continue to use
/// raw values until they are migrated incrementally (Core UX Phase 2-3).
enum MercantisSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    static let cardCornerRadius: CGFloat = 10
    static let controlCornerRadius: CGFloat = 6
    static let pillCornerRadius: CGFloat = 999
}
