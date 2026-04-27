//
//  CommandBarView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct CommandBarAction: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let badge: String?
    public let keywords: [String]
    public let isQuickAction: Bool
    public let action: () -> Void

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        badge: String? = nil,
        keywords: [String] = [],
        isQuickAction: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badge = badge
        self.keywords = keywords
        self.isQuickAction = isQuickAction
        self.action = action
    }
}

/// A Spotlight-like search/command overlay.
public struct CommandBarView: View {

    private static let prefixMap: [String: String] = [
        "new": "create",
        "list": "doctype",
        "open": "doctype",
        "report": "report",
        "dashboard": "dashboard",
        "setup": "setup"
    ]
    private static let maxPrefixTokens = 1

    @Binding var isPresented: Bool
    let actions: [CommandBarAction]
    let showsCancel: Bool

    @State private var query = ""
    @State private var selectedIndex = 0

    public init(
        isPresented: Binding<Bool>,
        actions: [CommandBarAction],
        showsCancel: Bool = true
    ) {
        self._isPresented = isPresented
        self.actions = actions
        self.showsCancel = showsCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultList
        }
        .background(MercantisTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MercantisTheme.border.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        .frame(maxWidth: 720)
        .onDisappear {
            query = ""
            selectedIndex = 0
        }
        .onMoveCommand(perform: moveSelection)
        #if os(macOS)
        .onExitCommand {
            guard showsCancel else { return }
            isPresented = false
        }
        #endif
    }

    private var filteredActions: [CommandBarAction] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            let quick = actions.filter(\.isQuickAction)
            let topMatches = actions.filter { !$0.isQuickAction }.prefix(8)
            return quick + topMatches
        }

        let lower = trimmedQuery.lowercased()
        let tokens = lower.split(maxSplits: Self.maxPrefixTokens, whereSeparator: \.isWhitespace)
        if let head = tokens.first.map(String.init),
           let badge = Self.prefixMap[head] {
            let rest = tokens.count > 1
                ? String(tokens[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            return actions.filter { action in
                action.badge?.lowercased() == badge
                    && (rest.isEmpty || actionMatches(action, query: rest))
            }
        }

        return actions.filter { actionMatches($0, query: lower) }
    }

    private func actionMatches(_ action: CommandBarAction, query: String) -> Bool {
        action.title.lowercased().contains(query)
            || (action.subtitle?.lowercased().contains(query) ?? false)
            || action.keywords.contains(where: { $0.lowercased().contains(query) })
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Jump to module, DocType, report, dashboard…", text: $query)
                .font(.title3)
                .textFieldStyle(.plain)
                .onChange(of: query) { _, _ in
                    selectedIndex = 0
                }
                .onSubmit {
                    triggerSelection()
                }

            if !query.isEmpty {
                Button(action: {
                    query = ""
                    selectedIndex = 0
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if showsCancel {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
            }
        }
        .padding()
    }

    @ViewBuilder
    private var resultList: some View {
        if filteredActions.isEmpty {
            Text(query.isEmpty ? "No commands available." : "No results for \"\(query)\"")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, result in
                        commandRow(result: result, isSelected: index == selectedIndex)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)
        }
    }

    private func commandRow(result: CommandBarAction, isSelected: Bool) -> some View {
        Button(action: {
            result.action()
            isPresented = false
        }) {
            HStack(spacing: 12) {
                Image(systemName: result.icon)
                    .frame(width: 20)
                    .foregroundStyle(MercantisTheme.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.body)
                    if let subtitle = result.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let badge = result.badge {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(isSelected ? MercantisTheme.surfaceMuted : Color.clear)
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !filteredActions.isEmpty else { return }
        switch direction {
        case .down:
            selectedIndex = min(selectedIndex + 1, filteredActions.count - 1)
        case .up:
            selectedIndex = max(selectedIndex - 1, 0)
        default:
            break
        }
    }

    private func triggerSelection() {
        guard filteredActions.indices.contains(selectedIndex) else { return }
        filteredActions[selectedIndex].action()
        isPresented = false
    }
}
