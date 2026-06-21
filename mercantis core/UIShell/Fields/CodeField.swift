//
//  CodeField.swift
//  mercantis core
//
//  Feature-parity with the Flutter `CodeField` (scalar_field_widgets.dart).
//  A monospace, multi-line text area for snippets / scripts. Stores a `String`.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct CodeField: View {
    @Binding var value: String
    let isReadOnly: Bool

    public init(value: Binding<String>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
    }

    public var body: some View {
        Group {
            if isReadOnly {
                Text(value.isEmpty ? "—" : value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextEditor(text: $value)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.separator, lineWidth: 1)
                    )
            }
        }
    }
}
