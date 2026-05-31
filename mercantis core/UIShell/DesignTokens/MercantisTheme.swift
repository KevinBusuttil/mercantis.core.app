import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public enum MercantisSemanticTone: Sendable {
    case accent
    case brand
    case success
    case warning
    case danger
    case info
    case muted
}

/// Semantic colour identity for a navigation module / domain. Used by the
/// sidebar to add subtle, low-opacity accents per module while keeping the
/// overall surface native and calm.
public enum MercantisModuleTone: Hashable, Sendable {
    case crm
    case selling
    case buying
    case stock
    case accounting
    case manufacturing
    case setup
    case platform
    case system
    case neutral
}

public enum MercantisTheme {

    // MARK: - Adaptive colour helper

    /// Builds a light/dark adaptive `Color` from sRGB component tuples so the
    /// design system can ship brand and module colours that resolve per
    /// appearance without an asset catalog (the package has no `.xcassets`).
    /// Falls back to the light variant on platforms without a dynamic API.
    static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #elseif os(iOS)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        return Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }

    // MARK: - Brand palette

    /// Mercantis brand primary — a deep indigo. Chosen to read as a distinct
    /// product colour rather than the stock macOS azure accent, while staying
    /// in the trustworthy blue-indigo enterprise family. Used for primary
    /// buttons and product identity (header / logo square, hero chrome).
    /// White text clears WCAG AAA in both appearances (≈7.9:1 light, ≈6.3:1
    /// dark).
    public static let brandPrimary = adaptive(
        light: (0.263, 0.220, 0.792),
        dark:  (0.310, 0.275, 0.898)
    )
    public static let brandPrimaryHover = adaptive(
        light: (0.310, 0.275, 0.898),
        dark:  (0.388, 0.400, 0.945)
    )
    public static let brandPrimaryPressed = adaptive(
        light: (0.215, 0.188, 0.639),
        dark:  (0.263, 0.220, 0.792)
    )
    /// Low-opacity brand fill for tinted cards, identity chips, and selected
    /// indicators where the system accent would feel non-native.
    public static let brandPrimarySoft = brandPrimary.opacity(0.12)
    public static let brandPrimaryBorder = brandPrimary.opacity(0.32)
    /// Secondary brand tone (blue-teal) — the indigo's partner, for sparing
    /// accents / illustrations.
    public static let brandSecondary = adaptive(
        light: (0.05, 0.45, 0.55),
        dark:  (0.22, 0.63, 0.73)
    )
    /// Optional brighter highlight, used very sparingly (e.g. focus glints).
    public static let brandAccent = adaptive(
        light: (0.00, 0.50, 0.62),
        dark:  (0.32, 0.74, 0.84)
    )

    // MARK: - System accent (native selection / control tint)

    /// The system accent is intentionally retained for selection and native
    /// control tint so the app still respects the user's macOS accent choice.
    /// Product identity uses `brandPrimary` instead.
    public static let accent = Color.accentColor
    public static let accentFillSoft = Color.accentColor.opacity(0.12)
    public static let accentBorder = Color.accentColor.opacity(0.34)

    public static let softFillOpacity = 0.14
    public static let warningFillOpacity = 0.16
    public static let success = adaptive(
        light: (0.13, 0.60, 0.32),
        dark:  (0.27, 0.74, 0.46)
    )
    public static let warning = adaptive(
        light: (0.72, 0.50, 0.05),
        dark:  (0.92, 0.70, 0.25)
    )
    public static let danger = adaptive(
        light: (0.78, 0.18, 0.18),
        dark:  (0.94, 0.38, 0.38)
    )
    public static let info = adaptive(
        light: (0.18, 0.36, 0.78),
        dark:  (0.40, 0.58, 0.96)
    )
    public static let selectionBackground = accentFillSoft
    public static let selectionForeground = accent
    public static let mutedBadge = Color.secondary.opacity(0.16)
    public static let inspectorHighlight = brandPrimary.opacity(0.08)
    public static let subtleSeparatorOpacity = 0.15
    /// `primary` now resolves to the Mercantis brand so any legacy call-site
    /// that styled "the primary action colour" inherits product identity.
    public static let primary = brandPrimary
    public static let primaryPressed = brandPrimaryPressed

    #if os(macOS)
    public static let background = Color(NSColor.windowBackgroundColor)
    public static let surface = Color(NSColor.controlBackgroundColor)
    public static let surfaceElevated = Color(NSColor.textBackgroundColor)
    public static let surfaceMuted = Color(NSColor.underPageBackgroundColor)
    public static let border = Color(NSColor.separatorColor)
    public static let textPrimary = Color(NSColor.labelColor)
    public static let textMuted = Color(NSColor.secondaryLabelColor)
    #else
    public static let background = Color(UIColor.systemGroupedBackground)
    public static let surface = Color(UIColor.secondarySystemGroupedBackground)
    public static let surfaceElevated = Color(UIColor.systemBackground)
    public static let surfaceMuted = Color(UIColor.tertiarySystemBackground)
    public static let border = Color(UIColor.separator)
    public static let textPrimary = Color(UIColor.label)
    public static let textMuted = Color(UIColor.secondaryLabel)
    #endif

    public static func tint(for tone: MercantisSemanticTone) -> Color {
        switch tone {
        case .accent:
            accent
        case .brand:
            brandPrimary
        case .success:
            success
        case .warning:
            warning
        case .danger:
            danger
        case .info:
            info
        case .muted:
            textMuted
        }
    }

    public static func fillSoft(for tone: MercantisSemanticTone) -> Color {
        switch tone {
        case .accent:
            accentFillSoft
        case .brand:
            brandPrimarySoft
        case .success:
            success.opacity(softFillOpacity)
        case .warning:
            warning.opacity(warningFillOpacity)
        case .danger:
            danger.opacity(softFillOpacity)
        case .info:
            info.opacity(softFillOpacity)
        case .muted:
            mutedBadge
        }
    }

    /// Module tints are adaptive so they read clearly in light mode without
    /// turning neon in dark mode (dark variants are lifted in brightness but
    /// kept slightly desaturated).
    public static func moduleTint(_ tone: MercantisModuleTone) -> Color {
        switch tone {
        case .crm:           return adaptive(light: (0.20, 0.47, 0.92), dark: (0.42, 0.62, 0.97)) // blue
        case .selling:       return adaptive(light: (0.13, 0.60, 0.40), dark: (0.32, 0.74, 0.52)) // green
        case .buying:        return adaptive(light: (0.86, 0.49, 0.14), dark: (0.94, 0.64, 0.34)) // orange
        case .stock:         return adaptive(light: (0.52, 0.34, 0.82), dark: (0.68, 0.52, 0.92)) // purple
        case .accounting:    return adaptive(light: (0.31, 0.29, 0.78), dark: (0.50, 0.48, 0.92)) // indigo
        case .manufacturing: return adaptive(light: (0.80, 0.32, 0.36), dark: (0.92, 0.48, 0.50)) // rust red
        case .setup:         return adaptive(light: (0.42, 0.45, 0.50), dark: (0.60, 0.64, 0.70)) // slate gray
        case .platform:      return adaptive(light: (0.10, 0.58, 0.72), dark: (0.32, 0.74, 0.86)) // cyan
        case .system:        return adaptive(light: (0.42, 0.45, 0.50), dark: (0.60, 0.64, 0.70))
        case .neutral:       return textMuted
        }
    }

    public static func moduleFill(_ tone: MercantisModuleTone) -> Color {
        moduleTint(tone).opacity(0.12)
    }

    public static func moduleBorder(_ tone: MercantisModuleTone) -> Color {
        moduleTint(tone).opacity(0.22)
    }
}

/// Primary action button — Mercantis brand fill, white label, distinct
/// pressed state, and a dimmed disabled state. macOS-appropriate sizing
/// (compact, not web-scale).
public struct MercantisPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }

        private var fill: Color {
            configuration.isPressed
                ? MercantisTheme.brandPrimaryPressed
                : MercantisTheme.brandPrimary
        }
    }
}

/// Secondary action button — native, calm, hairline-bordered. Reads as a
/// standard macOS push button without competing with the primary action.
public struct MercantisSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MercantisTheme.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MercantisTheme.border, lineWidth: 1)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
        }
    }
}

/// Destructive action button — danger tone kept restrained (soft fill +
/// danger label) rather than a loud solid red, in keeping with the calm
/// business tone.
public struct MercantisDestructiveButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration)
    }

    private struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MercantisTheme.danger)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MercantisTheme.danger.opacity(configuration.isPressed ? 0.20 : 0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MercantisTheme.danger.opacity(0.28), lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}

private struct MercantisSemanticBadgeModifier: ViewModifier {
    let tone: MercantisSemanticTone

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MercantisTheme.fillSoft(for: tone), in: Capsule())
            .foregroundStyle(MercantisTheme.tint(for: tone))
    }
}

private struct MercantisSidebarSelectionModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 2)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? MercantisTheme.selectionBackground : Color.clear)
            )
            .foregroundStyle(isActive ? MercantisTheme.selectionForeground : MercantisTheme.textPrimary)
    }
}

private struct MercantisBuilderSelectionModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? MercantisTheme.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(MercantisTheme.accentBorder)
                            : AnyShapeStyle(.separator.opacity(MercantisTheme.subtleSeparatorOpacity)),
                        lineWidth: 1
                    )
            )
    }
}

private struct MercantisInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Strip the platform-default TextField chrome and external label.
            // Without these, macOS Form contexts render the TextField's `title`
            // argument as an external left-aligned label, which collapses into
            // unreadable per-character columns inside narrow cells (e.g. child
            // tables with many columns). Both modifiers are safe no-ops for
            // non-TextField/labelled views.
            .textFieldStyle(.plain)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
    }
}

private struct MercantisPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
    }
}

private struct MercantisCardModifier: ViewModifier {
    var padding: CGFloat? = nil
    var tinted: Bool = false

    func body(content: Content) -> some View {
        let radius = MercantisSpacing.cardCornerRadius
        return content
            .padding(padding ?? MercantisSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tinted ? AnyShapeStyle(MercantisTheme.brandPrimarySoft) : AnyShapeStyle(MercantisTheme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        tinted ? MercantisTheme.brandPrimaryBorder : MercantisTheme.border.opacity(0.8),
                        lineWidth: 1
                    )
            )
            .accessibilityElement(children: .contain)
    }
}

struct MercantisSectionHeading: View {
    let title: String
    var tone: MercantisSemanticTone = .muted
    var symbol: String? = nil
    var showsDivider: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsDivider {
                Divider()
            }
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MercantisTheme.textMuted)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(MercantisTheme.textMuted)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

public extension View {
    func mercantisSemanticBadge(tone: MercantisSemanticTone = .muted) -> some View {
        modifier(MercantisSemanticBadgeModifier(tone: tone))
    }

    func mercantisSidebarSelection(isActive: Bool) -> some View {
        modifier(MercantisSidebarSelectionModifier(isActive: isActive))
    }

    func mercantisBuilderSelection(isSelected: Bool) -> some View {
        modifier(MercantisBuilderSelectionModifier(isSelected: isSelected))
    }

    func mercantisInput() -> some View {
        modifier(MercantisInputModifier())
    }

    /// Standard Core card surface — consistent corner radius, native surface
    /// fill, hairline border. Pass `tinted: true` for a subtle brand-tinted
    /// card (e.g. a highlighted call-to-action), or a custom `padding` (use
    /// `0` for rows that manage their own insets).
    func mercantisCard(padding: CGFloat? = nil, tinted: Bool = false) -> some View {
        modifier(MercantisCardModifier(padding: padding, tinted: tinted))
    }

    func mercantisPicker() -> some View {
        modifier(MercantisPickerModifier())
    }
}

// MARK: - Semantic ERP status tones

/// Maps the free-form status strings ERP documents carry (Draft, Submitted,
/// Paid, Overdue, Completed, …) onto a small, business-like semantic palette
/// so operational states can be scanned at a glance. Colour is never the only
/// signal — each tone also carries an SF Symbol, and badges always show text.
///
/// Unknown / unmapped statuses fall back to a neutral tone so a new workflow
/// state still renders sensibly rather than blank.
public enum MercantisStatusTone: Sendable, Hashable {
    case draft
    case submitted
    case paid
    case unpaid
    case overdue
    case cancelled
    case closed
    case completed
    case inProgress
    case stopped
    case ordered
    case lost
    case reconciled
    case active
    case inactive
    case neutral

    /// Best-effort classification of an arbitrary status string. Matching is
    /// case-insensitive and tolerant of spacing/punctuation (e.g. "In Progress",
    /// "in-progress", "InProgress" all resolve to `.inProgress`).
    public init(status raw: String) {
        let s = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = s.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        switch compact {
        case "draft", "open", "new":
            self = .draft
        case "tobill", "todeliver", "toreceive", "topay":
            self = .inProgress
        case "pending", "awaiting":
            self = .stopped
        case "submitted", "submit", "approved", "confirmed", "issued":
            self = .submitted
        case "paid":
            self = .paid
        case "overdue":
            self = .overdue
        case "unpaid":
            self = .unpaid
        case "cancelled", "canceled", "rejected", "returned", "failed", "error":
            self = .cancelled
        case "closed":
            self = .closed
        case "completed", "complete", "done", "delivered", "fulfilled", "received":
            self = .completed
        case "inprogress", "processing", "working", "partlypaid", "partiallypaid", "partlyordered":
            self = .inProgress
        case "stopped", "onhold", "hold", "suspended":
            self = .stopped
        case "ordered", "toorder", "ordering", "purchased":
            self = .ordered
        case "lost", "expired", "void":
            self = .lost
        case "reconciled", "settled", "cleared", "matched":
            self = .reconciled
        case "active", "enabled", "live":
            self = .active
        case "inactive", "disabled", "archived", "deactivated":
            self = .inactive
        default:
            // Keyword fallbacks for compound statuses not matched exactly.
            if s.contains("overdue") { self = .overdue }
            else if s.contains("unpaid") { self = .unpaid }
            else if s.contains("paid") { self = .paid }
            else if s.contains("cancel") || s.contains("reject") { self = .cancelled }
            else if s.contains("complete") || s.contains("done") { self = .completed }
            else if s.contains("progress") { self = .inProgress }
            else if s.contains("submit") || s.contains("approve") { self = .submitted }
            else if s.contains("close") { self = .closed }
            else if s.contains("active") { self = .active }
            else if s.contains("draft") { self = .draft }
            else { self = .neutral }
        }
    }

    /// The underlying semantic tone used for the colour treatment.
    public var semantic: MercantisSemanticTone {
        switch self {
        case .paid, .completed, .reconciled, .active:
            return .success
        case .submitted, .ordered, .inProgress:
            return .info
        case .unpaid, .stopped:
            return .warning
        case .overdue, .cancelled, .lost:
            return .danger
        case .draft, .closed, .inactive, .neutral:
            return .muted
        }
    }

    /// A glyph paired with the label so status is legible without relying on
    /// colour alone (accessibility + fast scanning).
    public var symbol: String {
        switch self {
        case .draft:      return "pencil.line"
        case .submitted:  return "paperplane.fill"
        case .paid:       return "checkmark.seal.fill"
        case .unpaid:     return "exclamationmark.circle"
        case .overdue:    return "exclamationmark.triangle.fill"
        case .cancelled:  return "xmark.circle"
        case .closed:     return "lock.fill"
        case .completed:  return "checkmark.circle.fill"
        case .inProgress: return "clock"
        case .stopped:    return "pause.circle"
        case .ordered:    return "shippingbox.fill"
        case .lost:       return "xmark.bin"
        case .reconciled: return "checkmark.seal"
        case .active:     return "circle.fill"
        case .inactive:   return "circle"
        case .neutral:    return "circle.dashed"
        }
    }

    /// Spoken description appended to the badge's accessibility label.
    public var accessibilityDescription: String {
        switch semantic {
        case .success: return "positive status"
        case .info:    return "in-progress status"
        case .warning: return "attention status"
        case .danger:  return "problem status"
        case .muted, .accent, .brand: return "neutral status"
        }
    }
}

/// Reusable, business-like status badge. Always shows text, pairs the label
/// with a tone glyph, and uses a soft tonal fill + hairline ring that reads
/// in both light and dark mode. Subtle by design — it should not shout.
public struct MercantisStatusBadge: View {
    private let text: String
    private let tone: MercantisStatusTone
    private let showsSymbol: Bool

    /// Builds a badge by classifying a raw status string. Empty strings render
    /// as "Draft" so unsaved records still read sensibly.
    public init(_ status: String, showsSymbol: Bool = true) {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed.isEmpty ? "Draft" : trimmed
        self.tone = MercantisStatusTone(status: trimmed)
        self.showsSymbol = showsSymbol
    }

    /// Builds a badge with an explicit tone (e.g. when the caller already
    /// derived the state from a typed lifecycle value rather than a string).
    public init(text: String, tone: MercantisStatusTone, showsSymbol: Bool = true) {
        self.text = text
        self.tone = tone
        self.showsSymbol = showsSymbol
    }

    public var body: some View {
        let colour = MercantisTheme.tint(for: tone.semantic)
        return HStack(spacing: 4) {
            if showsSymbol {
                Image(systemName: tone.symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(colour)
        .background(MercantisTheme.fillSoft(for: tone.semantic), in: Capsule())
        .overlay(Capsule().stroke(colour.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement()
        .accessibilityLabel(Text("\(text), \(tone.accessibilityDescription)"))
    }
}

#if DEBUG
#Preview("Status badges") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(
            ["Draft", "Submitted", "Paid", "Unpaid", "Overdue",
             "Cancelled", "Completed", "In Progress", "Stopped",
             "Ordered", "Lost", "Reconciled", "Active", "Inactive", "Closed"],
            id: \.self
        ) { status in
            MercantisStatusBadge(status)
        }
    }
    .padding()
}
#endif
