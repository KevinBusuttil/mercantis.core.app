import SwiftUI

private enum StatusBadgeType: String {
    case submitted
    case done
    case completed
    case validated
    case warning
    case attention
    case error
    case failed
    case draft
    case pending

    var accessibilityLabel: String {
        switch self {
        case .submitted, .done, .completed, .validated:
            "success status"
        case .warning, .attention:
            "warning status"
        case .error, .failed:
            "error status"
        case .draft, .pending:
            "pending status"
        }
    }
}

struct StatusBadge: View {
    let text: String

    private var badgeType: StatusBadgeType? {
        StatusBadgeType(rawValue: text.lowercased())
    }

    private var tone: MercantisSemanticTone {
        switch badgeType {
        case .submitted, .done, .completed, .validated:
            return .success
        case .warning, .attention:
            return .warning
        case .error, .failed:
            return .danger
        case .draft, .pending:
            return .muted
        case .none:
            return .info
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(MercantisTheme.fillSoft(for: tone), in: Capsule())
            .foregroundStyle(MercantisTheme.tint(for: tone))
            .accessibilityLabel("\(text), \(badgeType?.accessibilityLabel ?? "informational status")")
    }
}

#Preview("Light") {
    HStack(spacing: 8) {
        StatusBadge(text: "Submitted")
        StatusBadge(text: "Draft")
    }
    .padding()
    .background(DesignSystemPalette.windowBackground)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: 8) {
        StatusBadge(text: "Submitted")
        StatusBadge(text: "Draft")
    }
    .padding()
    .background(DesignSystemPalette.windowBackground)
    .preferredColorScheme(.dark)
}
