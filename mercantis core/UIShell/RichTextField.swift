//
//  RichTextField.swift
//  mercantis core
//
//  W7: Markdown-backed rich text editor for FieldType.richText. (ADR-033)
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct RichTextField: View {
    @Binding var value: String
    let isReadOnly: Bool
    @State private var mode: Mode = .edit

    private enum Mode: String, CaseIterable, Identifiable { case edit, preview; var id: String { rawValue } }

    public init(value: Binding<String>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isReadOnly {
                Picker("", selection: $mode) {
                    Text("Edit").tag(Mode.edit)
                    Text("Preview").tag(Mode.preview)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
            if isReadOnly || mode == .preview {
                preview
            } else {
                TextEditor(text: $value)
                    .frame(minHeight: 120)
                    .font(.body.monospaced())
                    .padding(6)
                    .background(MercantisTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var preview: some View {
        ScrollView {
            Text(rendered)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 120)
        .background(MercantisTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rendered: AttributedString {
        (try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(value)
    }
}
