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
    let onCreate: (() -> Void)?

    @State private var searchText = ""
    @State private var selectedStatus = "All"
    @State private var sortMode: SortMode = .updatedDescending

    public init(
        docType: DocType,
        documents: [Document],
        onSelect: ((Document) -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.docType = docType
        self.documents = documents
        self.onSelect = onSelect
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 0) {
            controlsBar

            if processedDocuments.isEmpty {
                emptyState
            } else {
                documentTable
            }
        }
        .background(MercantisTheme.background)
    }

    private var controlsBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search \(docType.name)…", text: $searchText)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Picker("Status", selection: $selectedStatus) {
                    ForEach(statusOptions, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                .pickerStyle(.menu)

                Picker("Sort", selection: $sortMode) {
                    ForEach(SortMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
            }
            .font(.caption)
        }
        .padding(10)
        .background(MercantisTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No \(docType.name) records")
                .font(.headline)
            Text("Adjust filters or create a new record.")
                .foregroundStyle(.secondary)
            if let onCreate {
                Button("Create \(docType.name)") {
                    onCreate()
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
            }
        }
        Spacer()
    }

    private var documentTable: some View {
        List(processedDocuments) { doc in
            Button(action: { onSelect?(doc) }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(titleValue(for: doc))
                            .font(.headline)
                        Spacer()
                        statusBadge(for: doc.status)
                    }

                    ForEach(displayFields, id: \.key) { field in
                        let value = displayValue(for: field.key, in: doc)
                        if value != "—" {
                            HStack(spacing: 6) {
                                Text(field.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(value)
                                    .font(.subheadline)
                            }
                        }
                    }

                    Text(doc.id)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var displayFields: [FieldDefinition] {
        let candidates = docType.fields.filter { $0.key != docType.titleField }
        let searchable = candidates.filter { $0.isSearchable || docType.searchFields.contains($0.key) }
        let source = searchable.isEmpty ? candidates : searchable
        return Array(source.prefix(3))
    }

    private var statusOptions: [String] {
        let statuses = Set(documents.map(\.status).filter { !$0.isEmpty })
        return ["All"] + statuses.sorted()
    }

    private var processedDocuments: [Document] {
        let lower = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = documents.filter { doc in
            let statusMatches = selectedStatus == "All" || doc.status == selectedStatus
            let searchMatches: Bool
            if lower.isEmpty {
                searchMatches = true
            } else {
                searchMatches = doc.id.lowercased().contains(lower)
                    || titleValue(for: doc).lowercased().contains(lower)
                    || docType.searchFields.contains(where: { key in
                        displayValue(for: key, in: doc).lowercased().contains(lower)
                    })
            }
            return statusMatches && searchMatches
        }

        return filtered.sorted { lhs, rhs in
            switch sortMode {
            case .updatedDescending:
                return lhs.updatedAt > rhs.updatedAt
            case .updatedAscending:
                return lhs.updatedAt < rhs.updatedAt
            case .titleAscending:
                return titleValue(for: lhs).localizedCaseInsensitiveCompare(titleValue(for: rhs)) == .orderedAscending
            case .titleDescending:
                return titleValue(for: lhs).localizedCaseInsensitiveCompare(titleValue(for: rhs)) == .orderedDescending
            }
        }
    }

    private func titleValue(for doc: Document) -> String {
        displayValue(for: docType.titleField, in: doc)
    }

    private func displayValue(for key: String, in doc: Document) -> String {
        switch doc.fields[key] {
        case .string(let s): return s.isEmpty ? "—" : s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "Yes" : "No"
        case .date(let d), .dateTime(let d): return ISO8601DateFormatter().string(from: d)
        case .data(let d): return "<\(d.count) bytes>"
        case .array(let xs): return "[\(xs.count) items]"
        case .null, nil: return "—"
        }
    }

    private func statusBadge(for status: String) -> some View {
        Text(status.isEmpty ? "Draft" : status)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MercantisTheme.primary.opacity(0.12))
            .clipShape(Capsule())
    }
}

private enum SortMode: String, CaseIterable {
    case updatedDescending
    case updatedAscending
    case titleAscending
    case titleDescending

    var title: String {
        switch self {
        case .updatedDescending: return "Updated ↓"
        case .updatedAscending: return "Updated ↑"
        case .titleAscending: return "Title A→Z"
        case .titleDescending: return "Title Z→A"
        }
    }
}
