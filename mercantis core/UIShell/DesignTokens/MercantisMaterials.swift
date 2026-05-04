import SwiftUI

/// Surface materials used to layer Mercantis Core UI without resorting to
/// heavy gradients or web-style decorative fills.
///
/// These map to native macOS materials and are intentionally subtle —
/// they should be used for hero header backings, inspector panes, and
/// section cards where a small amount of depth helps scan the screen.
enum MercantisMaterials {
    static let chrome: Material = .ultraThinMaterial
    static let surface: Material = .thinMaterial
    static let elevated: Material = .regularMaterial
    static let inspector: Material = .thickMaterial
}
