import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MercantisSemanticTone {
    case accent
    case success
    case warning
    case danger
    case info
    case muted
}

/// Semantic colour identity for a navigation module / domain. Used by the
/// sidebar to add subtle, low-opacity accents per module while keeping the
/// overall surface native and calm.
public enum MercantisModuleTone: Hashable, Sendable {
    case crm
    case selling
    case buying
    case stock
    case accounting
    case manufacturing
    case setup
    case platform
    case system
    case neutral
}

enum MercantisTheme {
    static let accent = Color.accentColor
    static let accentFillSoft = Color.accentColor.opacity(0.12)
    static let accentBorder = Color.accentColor.opacity(0.34)
    static let softFillOpacity = 0.14
    static let warningFillOpacity = 0.16
    static let success = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
    static let warning = Color(red: 202 / 255, green: 138 / 255, blue: 4 / 255)
    static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    static let info = Color(red: 67 / 255, green: 56 / 255, blue: 202 / 255)
    static let selectionBackground = accentFillSoft
    static let selectionForeground = accent
    static let mutedBadge = Color.secondary.opacity(0.16)
    static let inspectorHighlight = Color.accentColor.opacity(0.08)
    static let subtleSeparatorOpacity = 0.15
    static let primary = accent
    static let primaryPressed = Color.accentColor.opacity(0.88)

    #if os(macOS)
    static let background = Color(NSColor.windowBackgroundColor)
    static let surface = Color(NSColor.controlBackgroundColor)
    static let surfaceElevated = Color(NSColor.textBackgroundColor)
    static let surfaceMuted = Color(NSColor.underPageBackgroundColor)
    static let border = Color(NSColor.separatorColor)
    static let textPrimary = Color(NSColor.labelColor)
    static let textMuted = Color(NSColor.secondaryLabelColor)
    #else
    static let background = Color(UIColor.systemGroupedBackground)
    static let surface = Color(UIColor.secondarySystemGroupedBackground)
    static let surfaceElevated = Color(UIColor.systemBackground)
    static let surfaceMuted = Color(UIColor.tertiarySystemBackground)
    static let border = Color(UIColor.separator)
    static let textPrimary = Color(UIColor.label)
    static let textMuted = Color(UIColor.secondaryLabel)
    #endif

    static func tint(for tone: MercantisSemanticTone) -> Color {
        switch tone {
        case .accent:
            accent
        case .success:
            success
        case .warning:
            warning
        case .danger:
            danger
        case .info:
            info
        case .muted:
            textMuted
        }
    }

    static func fillSoft(for tone: MercantisSemanticTone) -> Color {
        switch tone {
        case .accent:
            accentFillSoft
        case .success:
            success.opacity(softFillOpacity)
        case .warning:
            warning.opacity(warningFillOpacity)
        case .danger:
            danger.opacity(softFillOpacity)
        case .info:
            info.opacity(softFillOpacity)
        case .muted:
            mutedBadge
        }
    }

    static func moduleTint(_ tone: MercantisModuleTone) -> Color {
        switch tone {
        case .crm:        return Color(red: 0.20, green: 0.47, blue: 0.96) // blue
        case .selling:    return Color(red: 0.13, green: 0.64, blue: 0.40) // green
        case .buying:     return Color(red: 0.90, green: 0.49, blue: 0.13) // orange
        case .stock:      return Color(red: 0.55, green: 0.34, blue: 0.85) // purple
        case .accounting:    return Color(red: 0.31, green: 0.27, blue: 0.80) // indigo
        case .manufacturing: return Color(red: 0.83, green: 0.32, blue: 0.36) // rust red
        case .setup:         return Color(red: 0.42, green: 0.45, blue: 0.50) // slate gray
        case .platform:   return Color(red: 0.10, green: 0.60, blue: 0.74) // cyan
        case .system:     return Color(red: 0.42, green: 0.45, blue: 0.50)
        case .neutral:    return textMuted
        }
    }

    static func moduleFill(_ tone: MercantisModuleTone) -> Color {
        moduleTint(tone).opacity(0.12)
    }

    static func moduleBorder(_ tone: MercantisModuleTone) -> Color {
        moduleTint(tone).opacity(0.22)
    }
}

struct MercantisPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? MercantisTheme.primaryPressed : MercantisTheme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(MercantisTheme.accentBorder.opacity(configuration.isPressed ? 0.7 : 1), lineWidth: 1)
            )
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

private struct MercantisSemanticBadgeModifier: ViewModifier {
    let tone: MercantisSemanticTone

    func body(content: Content) -> some View {
        content
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MercantisTheme.fillSoft(for: tone), in: Capsule())
            .foregroundStyle(MercantisTheme.tint(for: tone))
    }
}

private struct MercantisSidebarSelectionModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 2)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? MercantisTheme.selectionBackground : Color.clear)
            )
            .foregroundStyle(isActive ? MercantisTheme.selectionForeground : MercantisTheme.textPrimary)
    }
}

private struct MercantisBuilderSelectionModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? MercantisTheme.selectionBackground : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(MercantisTheme.accentBorder)
                            : AnyShapeStyle(.separator.opacity(MercantisTheme.subtleSeparatorOpacity)),
                        lineWidth: 1
                    )
            )
    }
}

private struct MercantisInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Strip the platform-default TextField chrome and external label.
            // Without these, macOS Form contexts render the TextField's `title`
            // argument as an external left-aligned label, which collapses into
            // unreadable per-character columns inside narrow cells (e.g. child
            // tables with many columns). Both modifiers are safe no-ops for
            // non-TextField/labelled views.
            .textFieldStyle(.plain)
            .labelsHidden()
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
    var tone: MercantisSemanticTone = .muted
    var symbol: String? = nil
    var showsDivider: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsDivider {
                Divider()
            }
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MercantisTheme.textMuted)
                }
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(MercantisTheme.textMuted)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

extension View {
    func mercantisSemanticBadge(tone: MercantisSemanticTone = .muted) -> some View {
        modifier(MercantisSemanticBadgeModifier(tone: tone))
    }

    func mercantisSidebarSelection(isActive: Bool) -> some View {
        modifier(MercantisSidebarSelectionModifier(isActive: isActive))
    }

    func mercantisBuilderSelection(isSelected: Bool) -> some View {
        modifier(MercantisBuilderSelectionModifier(isSelected: isSelected))
    }

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
