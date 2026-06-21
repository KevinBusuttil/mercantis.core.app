//
//  DurationField.swift
//  mercantis core
//
//  Feature-parity with the Flutter `DurationField` (scalar_field_widgets.dart).
//  Hours + minutes entry. Stores total seconds as an `Int` (matching the
//  Flutter storage), surfaced here through an `Int` binding.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct DurationField: View {
    /// Total duration in seconds. 0 means "unset".
    @Binding var seconds: Int
    let isReadOnly: Bool

    public init(seconds: Binding<Int>, isReadOnly: Bool) {
        self._seconds = seconds
        self.isReadOnly = isReadOnly
    }

    private var hoursBinding: Binding<String> {
        Binding<String>(
            get: { seconds / 3600 == 0 ? "" : "\(seconds / 3600)" },
            set: { recompute(hours: Int($0), minutes: nil) }
        )
    }

    private var minutesBinding: Binding<String> {
        Binding<String>(
            get: { (seconds % 3600) / 60 == 0 ? "" : "\((seconds % 3600) / 60)" },
            set: { recompute(hours: nil, minutes: Int($0)) }
        )
    }

    private func recompute(hours: Int?, minutes: Int?) {
        let h = hours ?? (seconds / 3600)
        let m = minutes ?? ((seconds % 3600) / 60)
        seconds = (h * 3600) + (m * 60)
    }

    public var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("0", text: hoursBinding)
                    .mercantisInput()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .disabled(isReadOnly)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Text("h").foregroundStyle(MercantisTheme.textMuted)
            }
            HStack(spacing: 4) {
                TextField("0", text: minutesBinding)
                    .mercantisInput()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .disabled(isReadOnly)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Text("m").foregroundStyle(MercantisTheme.textMuted)
            }
        }
    }
}
