import SwiftUI

struct StatusBadge: View {
    let text: String

    private var tintColor: Color {
        switch text.lowercased() {
        case "submitted", "done", "completed":
            return .green
        case "draft", "pending":
            return .gray
        default:
            return .blue
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tintColor.opacity(0.16), in: Capsule())
            .foregroundStyle(tintColor)
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
