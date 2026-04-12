//
//  CommandBarView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

/// A Spotlight-like search/command overlay.
///
/// Activated by ⌘K (desktop) or from the search tab (iPhone). Lets users search
/// across all registered DocTypes and navigate quickly to documents.
public struct CommandBarView: View {

    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var results: [CommandResult] = []

    /// Optional list of registered DocType names for result categorisation.
    var docTypeNames: [String]

    public init(
        isPresented: Binding<Bool>,
        docTypeNames: [String] = []
    ) {
        self._isPresented = isPresented
        self.docTypeNames = docTypeNames
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultList
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .frame(maxWidth: 600)
        .onDisappear { query = "" }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search or jump to…", text: $query)
                .font(.title3)
                .textFieldStyle(.plain)
                .onChange(of: query) { _, newValue in
                    updateResults(for: newValue)
                }

            if !query.isEmpty {
                Button(action: { query = ""; results = [] }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Cancel") {
                isPresented = false
            }
            .foregroundStyle(.blue)
        }
        .padding()
    }

    // MARK: - Result List

    @ViewBuilder
    private var resultList: some View {
        if results.isEmpty && !query.isEmpty {
            Text("No results for "\(query)"")
                .foregroundStyle(.secondary)
                .padding()
        } else if results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)
                ForEach(quickActions) { action in
                    commandRow(result: action)
                }
            }
            .padding(.bottom, 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(results) { result in
                        commandRow(result: result)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400)
        }
    }

    private func commandRow(result: CommandResult) -> some View {
        Button(action: {
            result.action()
            isPresented = false
        }) {
            HStack(spacing: 12) {
                Image(systemName: result.icon)
                    .frame(width: 20)
                    .foregroundStyle(.blue)

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    // MARK: - Results Logic

    private func updateResults(for text: String) {
        guard !text.isEmpty else {
            results = []
            return
        }
        let lower = text.lowercased()

        // Search DocType names.
        let docTypeResults = docTypeNames
            .filter { $0.lowercased().contains(lower) }
            .map { name in
                CommandResult(
                    id: "doctype-\(name)",
                    title: name,
                    subtitle: "DocType",
                    icon: "doc.text",
                    badge: "DocType",
                    action: {}
                )
            }

        results = docTypeResults
    }

    // MARK: - Quick Actions

    private var quickActions: [CommandResult] {
        [
            CommandResult(
                id: "qa-new",
                title: "Create New Document",
                subtitle: "Choose a DocType",
                icon: "plus.circle",
                badge: nil,
                action: {}
            ),
            CommandResult(
                id: "qa-home",
                title: "Go to Home",
                subtitle: nil,
                icon: "house",
                badge: nil,
                action: {}
            ),
            CommandResult(
                id: "qa-inbox",
                title: "Go to Inbox",
                subtitle: nil,
                icon: "tray",
                badge: nil,
                action: {}
            ),
        ]
    }
}

// MARK: - Command Result

private struct CommandResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String
    let badge: String?
    let action: () -> Void
}
