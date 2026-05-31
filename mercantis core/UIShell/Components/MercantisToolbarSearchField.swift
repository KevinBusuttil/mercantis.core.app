import SwiftUI

/// Compact, native-feeling search field for dashboard / document-workspace
/// toolbars and panel headers.
///
/// Intentionally smaller than a full-width form search box: a hairline-bordered
/// capsule with a leading magnifier and a trailing clear button that appears
/// only when there's text. Uses `.plain` field chrome so it sits cleanly inside
/// a toolbar without the heavy default bezel, while remaining fully keyboard
/// accessible (focus ring is preserved via the system focus state on the
/// underlying `TextField`).
public struct MercantisToolbarSearchField: View {
    @Binding private var text: String
    private let placeholder: String
    private let width: CGFloat?
    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        placeholder: String = "Search",
        width: CGFloat? = 220
    ) {
        self._text = text
        self.placeholder = placeholder
        self.width = width
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MercantisTheme.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { /* caller observes `text` */ }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(MercantisTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width)
        .background(
            Capsule(style: .continuous)
                .fill(MercantisTheme.surfaceMuted)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(isFocused ? MercantisTheme.accentBorder : MercantisTheme.hairline,
                        lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(placeholder))
    }
}

#if DEBUG
private struct MercantisToolbarSearchFieldPreview: View {
    @State private var query = ""
    @State private var filled = "Aurora Trading"
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MercantisToolbarSearchField(text: $query, placeholder: "Search documents")
            MercantisToolbarSearchField(text: $filled, placeholder: "Search")
        }
        .padding()
    }
}

#Preview("Toolbar search") {
    MercantisToolbarSearchFieldPreview()
}
#endif
