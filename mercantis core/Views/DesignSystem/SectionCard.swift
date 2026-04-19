import SwiftUI

struct SectionCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator.opacity(0.7), lineWidth: 1)
            )
    }
}

#Preview("Light") {
    SectionCard {
        VStack(alignment: .leading) {
            Text("Card Title").font(.headline)
            Text("Card body")
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(DesignSystemPalette.windowBackground)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    SectionCard {
        VStack(alignment: .leading) {
            Text("Card Title").font(.headline)
            Text("Card body")
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .background(DesignSystemPalette.windowBackground)
    .preferredColorScheme(.dark)
}
