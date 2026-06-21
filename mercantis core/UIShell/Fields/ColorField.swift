//
//  ColorField.swift
//  mercantis core
//
//  Feature-parity with the Flutter `ColorField` (color_field.dart). Stores a
//  `#RRGGBB` hex string. Shows the current swatch + hex; the native macOS/iOS
//  `ColorPicker` drives selection, and the chosen colour is written back as an
//  uppercase `#RRGGBB` string.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct ColorField: View {
    /// Backing `#RRGGBB` hex string ("" when unset).
    @Binding var value: String
    let isReadOnly: Bool

    public init(value: Binding<String>, isReadOnly: Bool) {
        self._value = value
        self.isReadOnly = isReadOnly
    }

    private var colorBinding: Binding<Color> {
        Binding<Color>(
            get: { Self.parseHex(value) ?? .clear },
            set: { value = Self.toHex($0) }
        )
    }

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Self.parseHex(value) ?? Color.secondary.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MercantisTheme.border, lineWidth: 1)
                )
            Text(value.isEmpty ? "No colour" : value.uppercased())
                .foregroundStyle(value.isEmpty ? .secondary : MercantisTheme.textPrimary)
            Spacer(minLength: 0)
            if !isReadOnly {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    /// Parses `#RRGGBB` (or `RRGGBB`) into a `Color`; returns nil when invalid.
    public static func parseHex(_ hex: String?) -> Color? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Encodes a `Color` to an uppercase `#RRGGBB` string.
    public static func toHex(_ color: Color) -> String {
#if os(macOS)
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int((resolved.redComponent * 255).rounded())
        let g = Int((resolved.greenComponent * 255).rounded())
        let b = Int((resolved.blueComponent * 255).rounded())
#else
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        UIColor(color).getRed(&rf, green: &gf, blue: &bf, alpha: &af)
        let r = Int((rf * 255).rounded())
        let g = Int((gf * 255).rounded())
        let b = Int((bf * 255).rounded())
#endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
