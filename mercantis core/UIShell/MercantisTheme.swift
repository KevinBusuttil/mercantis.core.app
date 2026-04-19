import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MercantisTheme {
    static let primary = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let primaryPressed = Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255)
    static let success = Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255)
    static let warning = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

    #if os(macOS)
    static let background = Color(NSColor.windowBackgroundColor)
    static let surface = Color(NSColor.controlBackgroundColor)
    static let surfaceMuted = Color(NSColor.underPageBackgroundColor)
    static let border = Color(NSColor.separatorColor)
    static let textPrimary = Color(NSColor.labelColor)
    static let textMuted = Color(NSColor.secondaryLabelColor)
    #else
    static let background = Color(UIColor.systemGroupedBackground)
    static let surface = Color(UIColor.secondarySystemGroupedBackground)
    static let surfaceMuted = Color(UIColor.tertiarySystemBackground)
    static let border = Color(UIColor.separator)
    static let textPrimary = Color(UIColor.label)
    static let textMuted = Color(UIColor.secondaryLabel)
    #endif
}

enum MercantisType {
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let sectionHead = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let meta = Font.system(size: 11, weight: .medium)
    static let mono = Font.system(size: 12, design: .monospaced)
}

struct MercantisPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? MercantisTheme.primaryPressed : MercantisTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct MercantisSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MercantisTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MercantisTheme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MercantisDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MercantisTheme.danger)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(MercantisTheme.danger.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

private struct MercantisInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
    }
}

private struct MercantisPickerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
    }
}

private struct MercantisCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MercantisTheme.border.opacity(0.8), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
    }
}

struct MercantisSectionHeading: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title.uppercased())
                .font(MercantisType.meta)
                .foregroundStyle(MercantisTheme.textMuted)
                .tracking(0.6)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension View {
    func mercantisInput() -> some View {
        modifier(MercantisInputModifier())
    }

    func mercantisCard() -> some View {
        modifier(MercantisCardModifier())
    }

    func mercantisPicker() -> some View {
        modifier(MercantisPickerModifier())
    }
}
