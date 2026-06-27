import SwiftUI

/// Compact workspace header used by record workspaces, dashboards, and
/// reports to clarify where the user is and what the primary action does.
///
/// Layout follows the Core UX direction (`Docs/UX-DIRECTION.md` §5.2):
///
///     [icon] Title
///     Subtitle copy explaining the workspace
///     [count] [module] [status]                       [+ Primary action]
///
/// The header is intentionally compact and native-feeling. It is not a
/// marketing banner — keep copy short and let SF Symbols carry identity.
public struct WorkspaceHeroHeader: View {
    public struct Badge: Identifiable, Hashable {
        public let id = UUID()
        public let text: String
        public let tone: Tone
        /// Optional hover tooltip explaining what the badge means — used to
        /// demystify chips like the module category for new users.
        public let help: String?

        public enum Tone: Hashable {
            case muted
            case accent
            case success
            case warning
            case info
        }

        public init(_ text: String, tone: Tone = .muted, help: String? = nil) {
            self.text = text
            self.tone = tone
            self.help = help
        }
    }

    let symbol: String
    let title: String
    let subtitle: String?
    let badges: [Badge]
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?

    public init(
        symbol: String = "rectangle.stack",
        title: String,
        subtitle: String? = nil,
        badges: [Badge] = [],
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
    }

    public var body: some View {
        HStack(alignment: .top, spacing: MercantisSpacing.m) {
            iconBadge

            VStack(alignment: .leading, spacing: MercantisSpacing.xs) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MercantisTheme.textMuted)
                        .lineLimit(2)
                }

                if !badges.isEmpty {
                    HStack(spacing: MercantisSpacing.s) {
                        ForEach(badges) { badge in
                            Text(badge.text)
                                .mercantisSemanticBadge(tone: badge.tone.semanticTone)
                                .help(badge.help ?? "")
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: MercantisSpacing.m)

            if let primaryActionTitle, let primaryAction {
                Button(action: primaryAction) {
                    Label(primaryActionTitle, systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                .accessibilityLabel(Text(primaryActionTitle))
            }
        }
        .padding(.horizontal, MercantisSpacing.l)
        .padding(.vertical, MercantisSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MercantisMaterials.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }

    private var iconBadge: some View {
        // Brand-tinted identity chip so every workspace header reads as part
        // of the Mercantis product rather than a generic accent-coloured view.
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(MercantisTheme.brandPrimary)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: MercantisSpacing.controlCornerRadius, style: .continuous)
                    .fill(MercantisTheme.brandPrimarySoft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MercantisSpacing.controlCornerRadius, style: .continuous)
                    .stroke(MercantisTheme.brandPrimaryBorder, lineWidth: 0.5)
            )
    }
}

extension WorkspaceHeroHeader.Badge.Tone {
    var semanticTone: MercantisSemanticTone {
        switch self {
        case .muted: .muted
        case .accent: .accent
        case .success: .success
        case .warning: .warning
        case .info: .info
        }
    }
}

#if DEBUG
#Preview("WorkspaceHeroHeader — full") {
    WorkspaceHeroHeader(
        symbol: "person.2",
        title: "Customers",
        subtitle: "Manage customer records, contacts, addresses and CRM activity.",
        badges: [
            .init("124 records"),
            .init("CRM", tone: .info),
            .init("Synced", tone: .success)
        ],
        primaryActionTitle: "New Customer",
        primaryAction: {}
    )
    .padding()
}

#Preview("WorkspaceHeroHeader — minimal") {
    WorkspaceHeroHeader(
        title: "Reports"
    )
    .padding()
}
#endif
