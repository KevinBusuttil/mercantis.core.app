//
//  GenericListView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

/// A SwiftUI view that renders a sortable, filterable list of documents
/// driven entirely by `DocType` metadata.
public struct GenericListView: View {

    let docType: DocType
    let documents: [Document]
    let onSelect: ((Document) -> Void)?

    @State private var searchText = ""
    @State private var sortFieldKey: String? = nil
    @State private var sortAscending = true

    public init(
        docType: DocType,
        documents: [Document],
        onSelect: ((Document) -> Void)? = nil
    ) {
        self.docType = docType
        self.documents = documents
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar

            if processedDocuments.isEmpty {
                Spacer()
                Text("No \(docType.name) records found.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                documentTable
            }
        }
        .navigationTitle(docType.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(processedDocuments.count) records")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search \(docType.name)…", text: $searchText)
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Document Table

    @ViewBuilder
    private var documentTable: some View {
        let columns = listColumns

        List(processedDocuments) { doc in
            Button(action: { onSelect?(doc) }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleValue(for: doc))
                        .font(.headline)
                    if columns.count > 1, let second = columns.dropFirst().first {
                        Text(displayValue(for: second.key, in: doc))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(doc.status)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Computed Properties

    private var listColumns: [FieldDefinition] {
        let searchFieldKeys = Set(docType.searchFields)
        return docType.fields.filter { field in
            field.isSearchable || searchFieldKeys.contains(field.key)
        }.prefix(5).map { $0 }
    }

    private var processedDocuments: [Document] {
        var result = documents

        // Filter by search text across searchable fields.
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter { doc in
                docType.searchFields.contains { key in
                    displayValue(for: key, in: doc).lowercased().contains(lower)
                } || doc.id.lowercased().contains(lower)
            }
        }

        // Sort by selected field.
        if let key = sortFieldKey {
            result.sort { a, b in
                let av = displayValue(for: key, in: a)
                let bv = displayValue(for: key, in: b)
                return sortAscending ? av < bv : av > bv
            }
        }

        return result
    }

    // MARK: - Helpers

    private func titleValue(for doc: Document) -> String {
        displayValue(for: docType.titleField, in: doc)
    }

    private func displayValue(for key: String, in doc: Document) -> String {
        switch doc.fields[key] {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "Yes" : "No"
        case .null, nil: return "—"
        }
    }
}
