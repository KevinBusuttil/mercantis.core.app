import SwiftUI

struct CodeEditorCard: View {
    @Binding var text: String

    private var lineNumbers: [Int] {
        let count = max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return Array(1...count)
    }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Script Editor")
                    .font(.headline)

                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(lineNumbers, id: \.self) { line in
                                Text("\(line)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(height: 20, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(width: 36)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.35))

                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 170)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.separator, lineWidth: 1)
                )
            }
        }
    }
}

#Preview("Light") {
    CodeEditorCard(text: .constant("let value = 42\nprint(value)"))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    CodeEditorCard(text: .constant("func build() {\n    // script\n}"))
        .padding()
        .background(DesignSystemPalette.windowBackground)
        .preferredColorScheme(.dark)
}
