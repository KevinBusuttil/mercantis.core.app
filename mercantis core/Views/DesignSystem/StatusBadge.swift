import SwiftUI

private enum SemanticBadgeStatus: String {
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
}

struct StatusBadge: View {
    let text: String

    private var tone: MercantisSemanticTone {
        switch SemanticBadgeStatus(rawValue: text.lowercased()) {
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
