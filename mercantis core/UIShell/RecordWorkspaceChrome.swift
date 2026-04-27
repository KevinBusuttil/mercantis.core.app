import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct RecordWorkspaceToolbarContent: ToolbarContent {
    let statusText: String
    @Binding var selectedViewMode: RecordViewMode
    let supportedViewModes: [RecordViewMode]
    let primaryActionTitle: String
    let onPrimaryAction: (() -> Void)?
    let overflowMenuContent: (() -> AnyView)?

    public init(
        statusText: String,
        selectedViewMode: Binding<RecordViewMode>,
        supportedViewModes: [RecordViewMode],
        primaryActionTitle: String = "New",
        onPrimaryAction: (() -> Void)? = nil,
        overflowMenuContent: (() -> AnyView)? = nil
    ) {
        self.statusText = statusText
        _selectedViewMode = selectedViewMode
        self.supportedViewModes = supportedViewModes
        self.primaryActionTitle = primaryActionTitle
        self.onPrimaryAction = onPrimaryAction
        self.overflowMenuContent = overflowMenuContent
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Text(statusText)
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        ToolbarItem(placement: .automatic) {
            Picker(LocalizedStringKey("Record View Mode"), selection: $selectedViewMode) {
                ForEach(supportedViewModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 220)
            .accessibilityLabel(Text("Record View Mode"))
        }

        if let onPrimaryAction {
            ToolbarItem(placement: .primaryAction) {
                Button(primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(MercantisPrimaryButtonStyle())
            }
        }

        if let overflowMenuContent {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    overflowMenuContent()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More workspace actions")
            }
        }
    }
}

public struct SelectedRecordHeader: View {
    let title: String
    let subtitle: String?
    let badges: [String]
    let actions: (() -> AnyView)?

    public init(
        title: String,
        subtitle: String? = nil,
        badges: [String] = [],
        actions: (() -> AnyView)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badges = badges
        self.actions = actions
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MercantisTheme.textMuted)
                }

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(badges.indices, id: \.self) { index in
                            Text(badges[index])
                                .mercantisSemanticBadge(tone: .muted)
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            if let actions {
                actions()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MercantisTheme.surface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

/// Returns a shared origin badge label used in selected-record headers.
/// - Parameters:
///   - isCustom: Whether the selected record is marked as custom.
///   - nonCustomLabel: The badge label used when the record is not custom.
/// - Returns: `"Custom"` when `isCustom` is true, otherwise `nonCustomLabel`.
internal func recordCustomizationBadge(isCustom: Bool, nonCustomLabel: String) -> String {
    isCustom ? "Custom" : nonCustomLabel
}
