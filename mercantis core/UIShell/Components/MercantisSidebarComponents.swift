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

    public init(systemImage: String, tone: MercantisModuleTone? = nil, isSelected: Bool = false) {
        self.systemImage = systemImage
        self.tone = tone
        self.isSelected = isSelected
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
        if let tone {
            return MercantisTheme.moduleFill(tone)
        }
        return isSelected ? MercantisTheme.accentFillSoft : Color.secondary.opacity(0.08)
    }

    private var tint: Color {
        if let tone {
            return MercantisTheme.moduleTint(tone)
        }
        return isSelected ? MercantisTheme.accent : MercantisTheme.textMuted
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

    public var body: some View {
        HStack(spacing: 9) {
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
                        isSelected
                            ? MercantisTheme.accentFillSoft
                            : Color.secondary.opacity(0.14),
                        in: Capsule()
                    )
                    .foregroundStyle(isSelected ? MercantisTheme.accent : .secondary)
            }
        }
        .padding(.leading, indentation)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? MercantisTheme.accentFillSoft : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(MercantisTheme.accent)
                    .frame(width: 2.5)
                    .padding(.vertical, 5)
                    .padding(.leading, indentation)
            }
        }
        .foregroundStyle(isSelected ? MercantisTheme.selectionForeground : MercantisTheme.textPrimary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
#endif
