import SwiftUI

enum MercantisTheme {
    static let primary = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let primaryPressed = Color(red: 30 / 255, green: 64 / 255, blue: 175 / 255)
    static let success = Color(red: 5 / 255, green: 150 / 255, blue: 105 / 255)
    static let warning = Color(red: 217 / 255, green: 119 / 255, blue: 6 / 255)
    static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

    static let background = Color(red: 244 / 255, green: 247 / 255, blue: 252 / 255)
    static let surface = Color.white
    static let surfaceMuted = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
    static let border = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
    static let textPrimary = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let textMuted = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
}

struct MercantisPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? MercantisTheme.primaryPressed : MercantisTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(MercantisTheme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct MercantisDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? MercantisTheme.danger.opacity(0.82) : MercantisTheme.danger)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct MercantisInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
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
                RoundedRectangle(cornerRadius: 8)
                    .fill(MercantisTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(MercantisTheme.border, lineWidth: 1)
            )
    }
}

private struct MercantisCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(MercantisTheme.surface)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MercantisTheme.textMuted)
                .tracking(0.5)
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
