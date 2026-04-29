//
//  LinkPickerField.swift
//  mercantis core
//
//  W4: search-and-pick UI for FieldType.link fields. (ADR-030)
//
//  Callers inject a `searchProvider` closure so this view stays independent
//  of `DocumentEngine`. When `searchProvider` is nil the field degrades to a
//  plain TextField — existing code that hasn't wired a provider yet continues
//  to compile and run unchanged.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// A form field that lets the user search for and select a linked document.
///
/// - `targetDocType`: display label for the target type (e.g. "Customer").
/// - `value`: binding to the persisted link value — the target document's ID string.
/// - `isReadOnly`: when true the field renders as plain text.
/// - `searchProvider`: given a (targetDocType, query) pair, returns matching
///   `Document` rows. Typically wraps `engine.list(docType:whereExpression:)`.
///   Pass `nil` to fall back to plain-text entry.
public struct LinkPickerField: View {

    let targetDocType: String
    @Binding var value: String
    let isReadOnly: Bool
    let searchProvider: ((String, String) -> [Document])?

    @State private var isPickerPresented = false
    @State private var searchQuery = ""
    @State private var searchResults: [Document] = []

    public init(
        targetDocType: String,
        value: Binding<String>,
        isReadOnly: Bool,
        searchProvider: ((String, String) -> [Document])?
    ) {
        self.targetDocType = targetDocType
        self._value = value
        self.isReadOnly = isReadOnly
        self.searchProvider = searchProvider
    }

    public var body: some View {
        if isReadOnly {
            Text(value.isEmpty ? "—" : value)
                .foregroundStyle(.secondary)
        } else if searchProvider == nil {
            // No provider: plain text entry (backwards-compatible fallback).
            HStack {
                TextField(targetDocType, text: $value)
                    .mercantisInput()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        } else {
            pickerButton
                .sheet(isPresented: $isPickerPresented, onDismiss: { searchQuery = "" }) {
                    pickerSheet
                }
        }
    }

    // MARK: - Picker button (idle state)

    private var pickerButton: some View {
        Button {
            searchResults = runSearch(query: "")
            isPickerPresented = true
        } label: {
            HStack {
                Text(value.isEmpty ? "Select \(targetDocType)…" : value)
                    .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(MercantisTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Picker sheet

    private var pickerSheet: some View {
        NavigationStack {
            List {
                if searchResults.isEmpty {
                    ContentUnavailableView(
                        searchQuery.isEmpty ? "No \(targetDocType) records" : "No results for \"\(searchQuery)\"",
                        systemImage: "magnifyingglass"
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(searchResults, id: \.id) { doc in
                        Button {
                            value = doc.id
                            isPickerPresented = false
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.id)
                                    .font(.body)
                                if let subtitle = firstStringFieldValue(doc) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(targetDocType)")
            .onChange(of: searchQuery) { _, query in
                searchResults = runSearch(query: query)
            }
            .navigationTitle("Select \(targetDocType)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPickerPresented = false }
                }
                // Allow clearing the current selection.
                if !value.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Clear") {
                            value = ""
                            isPickerPresented = false
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func runSearch(query: String) -> [Document] {
        searchProvider?(targetDocType, query) ?? []
    }

    /// Returns the first non-empty string field value from a document, used as
    /// a human-readable subtitle in the picker list alongside the raw ID.
    private func firstStringFieldValue(_ doc: Document) -> String? {
        for (key, value) in doc.fields {
            guard key != "name" else { continue }
            if case .string(let s) = value, !s.isEmpty, s != doc.id {
                return s
            }
        }
        return nil
    }
}
