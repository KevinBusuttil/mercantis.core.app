import SwiftUI

// MARK: - MercantisCard

/// Standard rounded business card surface used across dashboards, inspector
/// panels, and report sections.
///
/// Compared with the lightweight `.mercantisCard()` view modifier this is a
/// first-class container: it owns padding *variants*, an optional brand tint,
/// and an optional single soft shadow for floating surfaces. It deliberately
/// favours a hairline border over heavy shadows so dense ERP screens stay calm
/// (HIG: "use materials and subtle depth, not decorative drop shadows").
public struct MercantisCard<Content: View>: View {

    /// Padding rhythm. ERP grids want `.compact`; marketing-ish KPI rows want
    /// `.standard`. `.none` hands inset control to the caller (e.g. a table
    /// that draws its own row insets).
    public enum Padding: Sendable {
        case none, compact, standard, roomy

        var value: CGFloat {
            switch self {
            case .none:     return 0
            case .compact:  return MercantisSpacing.m
            case .standard: return MercantisSpacing.l
            case .roomy:    return MercantisSpacing.xl
            }
        }
    }

    private let padding: Padding
    private let tinted: Bool
    private let elevated: Bool
    private let content: Content

    public init(
        padding: Padding = .standard,
        tinted: Bool = false,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.tinted = tinted
        self.elevated = elevated
        self.content = content()
    }

    public var body: some View {
        let radius = MercantisSpacing.cardCornerRadius
        content
            .padding(padding.value)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tinted
                          ? AnyShapeStyle(MercantisTheme.brandPrimarySoft)
                          : AnyShapeStyle(MercantisTheme.surfaceCard))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tinted ? MercantisTheme.brandPrimaryBorder : MercantisTheme.hairline,
                            lineWidth: 1)
            )
            // A single shallow shadow only when explicitly elevated. The colour
            // is adaptive and collapses to nothing in dark mode where the border
            // already conveys separation.
            .shadow(color: elevated ? MercantisTheme.cardShadow : .clear,
                    radius: elevated ? 8 : 0, x: 0, y: elevated ? 3 : 0)
            .accessibilityElement(children: .contain)
    }
}

// MARK: - MercantisMetricCard

/// Compact KPI / metric card matching the reference dashboard's top row
/// (Total Sales, Gross Profit, Receivables, …).
///
/// Renders: optional icon, a muted uppercase-ish title, a large monospaced
/// value, and an optional delta chip with a comparison caption. The delta tone
/// (positive / negative / neutral) carries both colour *and* a directional
/// arrow glyph so the trend never relies on colour alone.
public struct MercantisMetricCard: View {

    public enum Trend: Sendable {
        case up, down, flat

        /// Classifies a signed change into a trend bucket. Exactly-zero (within
        /// a tiny epsilon) reads as flat.
        public init(change: Double) {
            if change > 0.00001 { self = .up }
            else if change < -0.00001 { self = .down }
            else { self = .flat }
        }

        var tint: Color {
            switch self {
            case .up:   return MercantisTheme.kpiPositive
            case .down: return MercantisTheme.kpiNegative
            case .flat: return MercantisTheme.kpiNeutral
            }
        }

        var symbol: String {
            switch self {
            case .up:   return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "arrow.right"
            }
        }
    }

    private let title: String
    private let value: String
    private let delta: String?
    private let trend: Trend
    private let comparison: String?
    private let systemImage: String?

    public init(
        title: String,
        value: String,
        delta: String? = nil,
        trend: Trend = .flat,
        comparison: String? = nil,
        systemImage: String? = nil
    ) {
        self.title = title
        self.value = value
        self.delta = delta
        self.trend = trend
        self.comparison = comparison
        self.systemImage = systemImage
    }

    public var body: some View {
        MercantisCard(padding: .standard) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MercantisTheme.brandPrimary)
                    }
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MercantisTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(size: 24, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(MercantisTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if delta != nil || comparison != nil {
                    HStack(spacing: 5) {
                        if let delta {
                            HStack(spacing: 2) {
                                Image(systemName: trend.symbol)
                                    .font(.system(size: 9, weight: .bold))
                                Text(delta)
                                    .font(.system(size: 11, weight: .semibold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(trend.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(trend.tint.opacity(0.12), in: Capsule())
                        }
                        if let comparison {
                            Text(comparison)
                                .font(.system(size: 10))
                                .foregroundStyle(MercantisTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        var parts = ["\(title), \(value)"]
        if let delta {
            let direction: String
            switch trend {
            case .up:   direction = "up"
            case .down: direction = "down"
            case .flat: direction = "unchanged"
            }
            parts.append("\(direction) \(delta)")
        }
        if let comparison { parts.append(comparison) }
        return parts.joined(separator: ", ")
    }

    // MARK: Pure formatting helpers (unit-tested)

    /// Formats a *fractional* change (0.125 → "+12.5%") as a signed percentage
    /// string. `nil` for a non-finite input. Pure — safe to unit test.
    public static func formatDeltaPercent(_ fraction: Double, decimals: Int = 1) -> String? {
        guard fraction.isFinite else { return nil }
        let pct = fraction * 100
        let sign = pct > 0 ? "+" : (pct < 0 ? "" : "")
        return "\(sign)\(String(format: "%.\(max(0, decimals))f", pct))%"
    }
}

// MARK: - MercantisPanelHeader

/// Title row for a dashboard widget / inspector / report section card.
///
/// Layout: `Title  (subtitle)            [trailing control]`. The title uses a
/// card-title weight; the optional trailing slot hosts a small control such as
/// a "See all" button or a period menu.
public struct MercantisPanelHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String?
    private let trailing: Trailing

    public init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MercantisSpacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MercantisTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: MercantisSpacing.s)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension MercantisPanelHeader where Trailing == EmptyView {
    /// Header without a trailing control.
    init(_ title: String, subtitle: String? = nil, systemImage: String? = nil) {
        self.init(title, subtitle: subtitle, systemImage: systemImage) { EmptyView() }
    }
}

// MARK: - MercantisInspectorCard

/// Right-side contextual card (customer / supplier / contact / summary) used in
/// document workspaces. A titled `MercantisCard` with compact padding tuned for
/// a narrow inspector column.
public struct MercantisInspectorCard<Content: View>: View {
    private let title: String
    private let systemImage: String?
    private let content: Content

    public init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        MercantisCard(padding: .compact) {
            VStack(alignment: .leading, spacing: MercantisSpacing.s) {
                MercantisPanelHeader(title, systemImage: systemImage)
                content
            }
        }
    }
}

/// A single `label : value` line for use inside `MercantisInspectorCard`.
/// Numeric values can be right-aligned and monospaced via `isNumeric`.
public struct MercantisInspectorRow: View {
    private let label: String
    private let value: String
    private let isNumeric: Bool

    public init(_ label: String, value: String, isNumeric: Bool = false) {
        self.label = label
        self.value = value
        self.isNumeric = isNumeric
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MercantisSpacing.s) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(MercantisTheme.textSecondary)
            Spacer(minLength: MercantisSpacing.s)
            Text(value)
                .font(.system(size: 12, weight: isNumeric ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(MercantisTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - MercantisEmptyState

/// Soft, useful empty state for dashboards, lists, and reports. Replaces raw
/// "no data" text with a centred SF Symbol, a short title, a one-line
/// explanation, and an optional call-to-action.
public struct MercantisEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        systemImage: String = "tray",
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: MercantisSpacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(MercantisTheme.textTertiary)
                .padding(.bottom, 2)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MercantisTheme.textPrimary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(MercantisTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MercantisSecondaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MercantisSpacing.xl)
        .padding(.horizontal, MercantisSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Metric cards") {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
        MercantisMetricCard(title: "Total Sales", value: "€48,250",
                            delta: "+12.5%", trend: .up,
                            comparison: "vs last month", systemImage: "eurosign.circle")
        MercantisMetricCard(title: "Gross Profit", value: "€18,900",
                            delta: "+4.1%", trend: .up,
                            comparison: "vs last month", systemImage: "chart.line.uptrend.xyaxis")
        MercantisMetricCard(title: "Receivables", value: "€9,430",
                            delta: "-3.2%", trend: .down,
                            comparison: "overdue €1,200", systemImage: "tray.and.arrow.down")
        MercantisMetricCard(title: "Stock Value", value: "€72,100",
                            systemImage: "shippingbox")
        MercantisMetricCard(title: "Orders to Deliver", value: "14",
                            delta: "0%", trend: .flat,
                            comparison: "same as yesterday", systemImage: "shippingbox.and.arrow.backward")
    }
    .padding()
    .frame(width: 720)
}

#Preview("Panel + inspector + empty") {
    HStack(alignment: .top, spacing: 16) {
        MercantisCard {
            VStack(alignment: .leading, spacing: 12) {
                MercantisPanelHeader("Recent Documents",
                                     subtitle: "Last 7 days",
                                     systemImage: "doc.text") {
                    Button("See all") {}
                        .buttonStyle(.link)
                        .font(.system(size: 11, weight: .semibold))
                }
                MercantisEmptyState(systemImage: "doc.text.magnifyingglass",
                                    title: "No documents yet",
                                    message: "Create a sales order or invoice and it will show up here.",
                                    actionTitle: "New Document") {}
            }
        }
        .frame(width: 360)

        VStack(spacing: 12) {
            MercantisInspectorCard("Customer", systemImage: "person.crop.circle") {
                VStack(alignment: .leading, spacing: 4) {
                    MercantisInspectorRow("Name", value: "Aurora Trading Ltd")
                    MercantisInspectorRow("Email", value: "ap@aurora.example")
                    MercantisInspectorRow("Terms", value: "Net 30")
                }
            }
            MercantisInspectorCard("Summary", systemImage: "sum") {
                VStack(alignment: .leading, spacing: 4) {
                    MercantisInspectorRow("Subtotal", value: "€1,200.00", isNumeric: true)
                    MercantisInspectorRow("Tax", value: "€216.00", isNumeric: true)
                    Divider()
                    MercantisInspectorRow("Total", value: "€1,416.00", isNumeric: true)
                }
            }
        }
        .frame(width: 260)
    }
    .padding()
    .frame(width: 680)
}
#endif
