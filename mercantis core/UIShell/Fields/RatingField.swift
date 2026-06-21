//
//  RatingField.swift
//  mercantis core
//
//  Feature-parity with the Flutter `RatingField` (scalar_field_widgets.dart).
//  A 1–5 tappable star picker. Stores an `Int` (0 = no rating). Tapping the
//  current rating again clears it.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct RatingField: View {
    @Binding var value: Int
    let isReadOnly: Bool
    let max: Int

    public init(value: Binding<Int>, isReadOnly: Bool, max: Int = 5) {
        self._value = value
        self.isReadOnly = isReadOnly
        self.max = max
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max, id: \.self) { i in
                Button {
                    guard !isReadOnly else { return }
                    // Tapping the current rating again clears it.
                    value = (i == value) ? 0 : i
                } label: {
                    Image(systemName: i <= value ? "star.fill" : "star")
                        .foregroundStyle(i <= value ? Color.yellow : MercantisTheme.textMuted)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(isReadOnly)
            }
        }
    }
}
