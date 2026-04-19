import SwiftUI

struct ActionCard: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview("Light") {
    ActionCard(icon: "doc.badge.plus", title: "Create Doctype", description: "Define a metadata-driven document schema.") {}
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ActionCard(icon: "chart.bar.doc.horizontal", title: "Create Report", description: "Build SQL-backed and visual reports.") {}
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
