import SwiftUI

// MARK: - Icon chip

/// Compact rounded icon container for sidebar rows and module headers.
///
/// The chip pairs an SF Symbol with a low-opacity tonal fill so different
/// modules read at a glance without colouring large surfaces. When a `tone`
/// is supplied the chip reflects the module identity; when no tone is given
/// the chip falls back to a neutral fill that lights up on selection.
public struct MercantisSidebarIconChip: View {
    public let systemImage: String
    public let tone: MercantisModuleTone?
    public var isSelected: Bool

    /// Mirrors the row: `.increased` when the platform paints the strong accent
    /// selection behind us, so the chip can switch to a white-on-translucent
    /// treatment rather than keeping its module colour on a blue background.
    @Environment(\.backgroundProminence) private var backgroundProminence

    public init(systemImage: String, tone: MercantisModuleTone? = nil, isSelected: Bool = false) {
        self.systemImage = systemImage
        self.tone = tone
        self.isSelected = isSelected
    }

    private var emphasis: MercantisTheme.SidebarRowEmphasis {
        MercantisTheme.sidebarRowEmphasis(
            isSelected: isSelected,
            isEmphasized: backgroundProminence == .increased
        )
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        // On a selected row the module colour is dropped: a brand/module chip on
        // top of the accent selection is the blue-on-blue bug. Use a subtle
        // white translucent fill on the strong selection, an accent-soft fill on
        // the muted selection, and only show the module tint when unselected.
        switch emphasis {
        case .emphasizedSelection:
            return Color.white.opacity(0.22)
        case .mutedSelection:
            return MercantisTheme.accentFillSoft
        case .normal:
            if let tone {
                return MercantisTheme.moduleFill(tone)
            }
            return Color.secondary.opacity(0.08)
        }
    }

    private var tint: Color {
        switch emphasis {
        case .emphasizedSelection:
            return MercantisTheme.selectionForegroundEmphasized
        case .mutedSelection:
            return MercantisTheme.accent
        case .normal:
            if let tone {
                return MercantisTheme.moduleTint(tone)
            }
            return MercantisTheme.textMuted
        }
    }
}

// MARK: - Row

/// Polished sidebar row preserving native list rhythm while adding a
/// coloured icon chip, optional count badge, and a clear selected state.
public struct MercantisSidebarRow: View {
    public let title: String
    public let systemImage: String
    public var tone: MercantisModuleTone?
    public var isSelected: Bool
    public var badge: String?
    public var indentation: CGFloat

    /// `.increased` when the parent `List(selection:)` is painting the strong
    /// (focused) accent selection behind this row; `.standard` for an unfocused
    /// / muted selection or a normal row. Drives the high-contrast foreground.
    @Environment(\.backgroundProminence) private var backgroundProminence

    public init(
        title: String,
        systemImage: String,
        tone: MercantisModuleTone? = nil,
        isSelected: Bool = false,
        badge: String? = nil,
        indentation: CGFloat = 0
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.isSelected = isSelected
        self.badge = badge
        self.indentation = indentation
    }

    private var emphasis: MercantisTheme.SidebarRowEmphasis {
        MercantisTheme.sidebarRowEmphasis(
            isSelected: isSelected,
            isEmphasized: backgroundProminence == .increased
        )
    }

    public var body: some View {
        // On the strong accent selection the leading rule, badge and any fill
        // switch to the high-contrast (white) treatment so nothing reads as
        // blue/purple-on-blue; the unfocused selection keeps the accent tones.
        let highContrast = emphasis.usesHighContrastForeground

        return HStack(spacing: 9) {
            MercantisSidebarIconChip(
                systemImage: systemImage,
                tone: tone,
                isSelected: isSelected
            )

            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        badgeBackground(highContrast: highContrast),
                        in: Capsule()
                    )
                    .foregroundStyle(badgeForeground(highContrast: highContrast))
            }
        }
        .padding(.leading, indentation)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            // Only draw our own soft fill for the muted/unfocused selection;
            // the strong selection background is owned by the native list, so
            // layering an accent wash there would muddy it.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(emphasis == .mutedSelection ? MercantisTheme.accentFillSoft : Color.clear)
        )
        .overlay(alignment: .leading) {
            // Colour is never the only selection signal: keep a leading rule on
            // every selected row, tinted white on the strong selection and
            // accent on the muted one so it stays visible against either fill.
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(highContrast ? MercantisTheme.selectionForegroundEmphasized : MercantisTheme.accent)
                    .frame(width: 2.5)
                    .padding(.vertical, 5)
                    .padding(.leading, indentation)
            }
        }
        .foregroundStyle(emphasis.foreground)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func badgeBackground(highContrast: Bool) -> Color {
        if highContrast {
            return Color.white.opacity(0.22)
        }
        return isSelected ? MercantisTheme.accentFillSoft : Color.secondary.opacity(0.14)
    }

    private func badgeForeground(highContrast: Bool) -> Color {
        if highContrast {
            return MercantisTheme.selectionForegroundEmphasized
        }
        return isSelected ? MercantisTheme.accent : .secondary
    }
}

// MARK: - Module header

/// Section header for a navigation module, with a tonal icon chip, bold
/// title, and optional count badge. Designed for use inside a sidebar
/// `Section`'s `header:` slot.
public struct MercantisSidebarModuleHeader: View {
    public let title: String
    public let systemImage: String
    public let tone: MercantisModuleTone
    public var badge: String?

    public init(
        title: String,
        systemImage: String,
        tone: MercantisModuleTone,
        badge: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.badge = badge
    }

    public var body: some View {
        HStack(spacing: 8) {
            MercantisSidebarIconChip(systemImage: systemImage, tone: tone)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(MercantisTheme.textPrimary)
                .textCase(nil)

            Spacer(minLength: 6)

            if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MercantisTheme.moduleFill(tone), in: Capsule())
                    .foregroundStyle(MercantisTheme.moduleTint(tone))
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Group header

/// Refined uppercase group header used to subdivide a module's items.
/// Tapping the header toggles a collapsed state owned by the caller.
public struct MercantisSidebarGroupHeader: View {
    public let title: String
    public let isCollapsed: Bool
    public let action: () -> Void

    public init(title: String, isCollapsed: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isCollapsed = isCollapsed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.tertiary)

                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .textCase(nil)

                Spacer()
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Text("\(title), \(isCollapsed ? "collapsed" : "expanded")"))
    }
}

// MARK: - Brand header

/// Compact product identity used at the top of a sidebar.
///
/// Designed to feel like a small native section, not a marketing banner:
/// fixed-size accent square + title + sub-label.
public struct MercantisSidebarBrandHeader: View {
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public var tint: Color?

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String = "shippingbox",
        tint: Color? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                // Brand colour by default so the product identity square is
                // recognisably Mercantis rather than the user's system accent.
                .fill(tint ?? MercantisTheme.brandPrimary)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: systemImage)
                        .foregroundStyle(.white)
                        .font(.system(size: 13, weight: .semibold))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Sidebar components") {
    List {
        Section {
            MercantisSidebarRow(
                title: "Customers",
                systemImage: "person.2",
                tone: .crm,
                isSelected: true,
                badge: "124"
            )
            MercantisSidebarRow(
                title: "Contacts",
                systemImage: "person.crop.circle",
                tone: .crm,
                badge: "32"
            )
        } header: {
            MercantisSidebarModuleHeader(
                title: "CRM",
                systemImage: "person.2",
                tone: .crm,
                badge: "4"
            )
        }
        Section {
            MercantisSidebarGroupHeader(title: "Catalogue", isCollapsed: false) {}
            MercantisSidebarRow(
                title: "Items",
                systemImage: "cube.box",
                tone: .selling
            )
        } header: {
            MercantisSidebarModuleHeader(
                title: "Selling",
                systemImage: "cart",
                tone: .selling
            )
        }
    }
    .listStyle(.sidebar)
    .frame(width: 260, height: 360)
}

/// Verifies the selected-row foreground stays high-contrast on the strong
/// accent selection (the blue-on-blue regression). The strong selection sets
/// `\.backgroundProminence` to `.increased`; here we force it so the selected
/// rows render with white text + a white-translucent chip rather than the
/// module/accent tint — readable in both light and dark mode.
#Preview("Selected row contrast") {
    func rows() -> some View {
        List {
            Section {
                MercantisSidebarRow(title: "Account", systemImage: "list.bullet.rectangle", tone: .accounting, isSelected: true)
                MercantisSidebarRow(title: "Customers", systemImage: "person.2", tone: .crm, isSelected: true, badge: "124")
                MercantisSidebarRow(title: "Stock Movements", systemImage: "tray.full", tone: .stock, isSelected: true)
            } header: {
                MercantisSidebarModuleHeader(title: "Selected (emphasized)", systemImage: "checkmark", tone: .accounting)
            }
        }
        .listStyle(.sidebar)
        // Paint the strong accent behind the rows and mark the selection as
        // emphasized so the preview matches a focused native sidebar selection.
        .scrollContentBackground(.hidden)
        .background(MercantisTheme.accent)
        .environment(\.backgroundProminence, .increased)
        .frame(width: 260, height: 200)
    }

    return VStack(spacing: 0) {
        rows().environment(\.colorScheme, .light)
        rows().environment(\.colorScheme, .dark)
    }
}
#endif
