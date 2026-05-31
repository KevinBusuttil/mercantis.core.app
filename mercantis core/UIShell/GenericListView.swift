//
//  GenericListView.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//
//  Metadata-driven DocType list with a native macOS filter bar: search,
//  built-in/saved views, type-aware field filters (incl. link & date
//  presets), sortable columns, active-filter count, distinct empty states,
//  and per-DocType persistence. Built on Core's `RecordListViewDefinition` /
//  `ListFilter` / `ListSort` model so the same predicates the UI builds can
//  be pushed into `DocumentEngine.list(...)` by an engine-backed consumer.
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// A SwiftUI view that renders a sortable, filterable list of documents
/// driven entirely by `DocType` metadata.
public struct GenericListView: View {

    let docType: DocType
    let documents: [Document]
    let selectedDocumentID: String?
    let onSelect: ((Document) -> Void)?
    let onCreate: (() -> Void)?
    /// Built-in / saved views (e.g. Hub's "Unpaid", "Overdue"). When empty the
    /// view synthesises status chips from the loaded data so every DocType
    /// still gets quick status filtering.
    let listViews: [RecordListViewDefinition]
    /// Stable key for persisting the selected view + sort per DocType.
    let preferenceKey: String?
    /// Link providers reused for link-field filters — same pattern as forms.
    let linkSearchProvider: ((String, String) -> [Document])?
    let linkResolveProvider: ((String, String) -> Document?)?
    let linkTargetMetaProvider: ((String) -> DocType?)?

    @State private var searchText = ""
    @State private var selectedViewID: String = "all"
    @State private var fieldFilters: [ActiveFieldFilter] = []
    @State private var sortFieldKey: String = "updatedAt"
    @State private var sortAscending: Bool = false
    @State private var addingFilterField: FieldDefinition?
    @State private var didRestore = false

    // MARK: - Inits

    /// Backward-compatible init — existing callers compile unchanged and get
    /// the synthesised status chips for free (no saved views, no link filters).
    public init(
        docType: DocType,
        documents: [Document],
        selectedDocumentID: String? = nil,
        onSelect: ((Document) -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.init(
            docType: docType,
            documents: documents,
            selectedDocumentID: selectedDocumentID,
            onSelect: onSelect,
            onCreate: onCreate,
            listViews: [],
            preferenceKey: nil,
            linkSearchProvider: nil,
            linkResolveProvider: nil,
            linkTargetMetaProvider: nil
        )
    }

    /// Full init exposing saved views, persistence, and link-filter providers.
    public init(
        docType: DocType,
        documents: [Document],
        selectedDocumentID: String? = nil,
        onSelect: ((Document) -> Void)? = nil,
        onCreate: (() -> Void)? = nil,
        listViews: [RecordListViewDefinition] = [],
        preferenceKey: String? = nil,
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        linkResolveProvider: ((String, String) -> Document?)? = nil,
        linkTargetMetaProvider: ((String) -> DocType?)? = nil
    ) {
        self.docType = docType
        self.documents = documents
        self.selectedDocumentID = selectedDocumentID
        self.onSelect = onSelect
        self.onCreate = onCreate
        self.listViews = listViews
        self.preferenceKey = preferenceKey
        self.linkSearchProvider = linkSearchProvider
        self.linkResolveProvider = linkResolveProvider
        self.linkTargetMetaProvider = linkTargetMetaProvider
    }

    public var body: some View {
        VStack(spacing: 0) {
            filterBar

            if processedDocuments.isEmpty {
                emptyState
            } else {
                documentTable
            }
        }
        .background(MercantisTheme.background)
        .onAppear(perform: restorePreferencesOnce)
        .onChange(of: selectedViewID) { _, _ in persistPreferences() }
        .onChange(of: sortFieldKey) { _, _ in persistPreferences() }
        .onChange(of: sortAscending) { _, _ in persistPreferences() }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Row 1 — search + sort + active-filter count + clear.
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search \(docType.name)…", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(MercantisTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                addFilterMenu
                sortMenu

                if hasActiveFilters {
                    Button {
                        clearAllFilters()
                    } label: {
                        Label("Clear (\(activeFilterCount))", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Row 2 — view chips (saved views or synthesised status chips).
            if viewChips.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewChips) { view in
                            chip(
                                label: view.label,
                                systemImage: view.systemImage,
                                isSelected: selectedViewID == view.id
                            ) {
                                selectView(view)
                            }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Row 3 — active field-filter chips.
            if !fieldFilters.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(fieldFilters) { filter in
                            removableChip(filter)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }

            // Row 4 — result count.
            HStack {
                Text(resultCountText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
        .background(MercantisTheme.surfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var addFilterMenu: some View {
        Menu {
            ForEach(filterableFields, id: \.key) { field in
                Button {
                    addingFilterField = field
                } label: {
                    Label(field.label, systemImage: symbol(for: field.type))
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(item: $addingFilterField) { field in
            FieldFilterEditor(
                field: field,
                linkSearchProvider: linkSearchProvider,
                linkResolveProvider: linkResolveProvider,
                linkTargetMeta: field.linkedDocType.flatMap { linkTargetMetaProvider?($0) },
                onApply: { predicate, display in
                    applyFieldFilter(field: field, predicate: predicate, display: display)
                    addingFilterField = nil
                },
                onCancel: { addingFilterField = nil }
            )
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(sortOptions, id: \.fieldKey) { option in
                Button {
                    if sortFieldKey == option.fieldKey {
                        sortAscending.toggle()
                    } else {
                        sortFieldKey = option.fieldKey
                        sortAscending = option.defaultAscending
                    }
                } label: {
                    if sortFieldKey == option.fieldKey {
                        Label(option.label, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label(currentSortLabel, systemImage: "arrow.up.arrow.down")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func chip(label: String, systemImage: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? MercantisTheme.accent : MercantisTheme.surface)
            .foregroundStyle(isSelected ? Color.white : MercantisTheme.textPrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(MercantisTheme.border, lineWidth: isSelected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func removableChip(_ filter: ActiveFieldFilter) -> some View {
        HStack(spacing: 4) {
            Text(filter.display)
                .font(.caption)
            Button {
                fieldFilters.removeAll { $0.id == filter.id }
            } label: {
                Image(systemName: "xmark.circle.fill").imageScale(.small)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(MercantisTheme.accentFillSoft)
        .foregroundStyle(MercantisTheme.textPrimary)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MercantisTheme.accentBorder, lineWidth: 1))
    }

    // MARK: - Empty states (three distinct cases)

    @ViewBuilder
    private var emptyState: some View {
        Spacer()
        if documents.isEmpty {
            emptyBox(
                icon: "tray",
                title: "No \(docType.name) yet",
                message: "Create your first \(docType.name) to get started.",
                actionTitle: onCreate != nil ? "Create \(docType.name)" : nil,
                action: onCreate
            )
        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyBox(
                icon: "magnifyingglass",
                title: "No records found for “\(searchText)”",
                message: "Try a different search term.",
                actionTitle: "Clear Search",
                action: { searchText = "" }
            )
        } else {
            emptyBox(
                icon: "line.3.horizontal.decrease.circle",
                title: "No \(docType.name) match these filters",
                message: "Adjust or clear the active filters to see more records.",
                actionTitle: "Clear Filters",
                action: { clearAllFilters() }
            )
        }
        Spacer()
    }

    private func emptyBox(icon: String, title: String, message: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(MercantisPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Document table (row rendering unchanged)

    private var documentTable: some View {
        List(processedDocuments) { doc in
            let isSelected = doc.id == selectedDocumentID
            Button(action: { onSelect?(doc) }) {
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isSelected ? MercantisTheme.accent : Color.clear)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(titleValue(for: doc))
                                .font(.headline)
                                .fontWeight(isSelected ? .bold : .semibold)
                                .foregroundStyle(isSelected ? MercantisTheme.accent : MercantisTheme.textPrimary)
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
                                        .lineLimit(field.type == .richText ? 1 : nil)
                                        .truncationMode(.tail)
                                }
                            }
                        }

                        Text(doc.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? MercantisTheme.accentFillSoft : Color.clear)
                )
                .contentShape(Rectangle())
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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

    // MARK: - Views (saved or synthesised)

    /// The chip row: app-provided views prefixed with "All", or — when none
    /// are supplied — synthesised status chips so every DocType still gets
    /// quick status filtering (A.2).
    private var viewChips: [RecordListViewDefinition] {
        if !listViews.isEmpty {
            if listViews.contains(where: { $0.id == "all" }) { return listViews }
            return [.all()] + listViews
        }
        return synthesisedStatusViews
    }

    private var synthesisedStatusViews: [RecordListViewDefinition] {
        var views: [RecordListViewDefinition] = [.all()]
        if docType.isSubmittable {
            views.append(RecordListViewDefinition(
                id: "draft", label: "Draft", systemImage: "pencil",
                predicates: [ListFilter("docStatus", .eq(.int(0)))]
            ))
            views.append(RecordListViewDefinition(
                id: "submitted", label: "Submitted", systemImage: "checkmark.seal",
                predicates: [ListFilter("docStatus", .eq(.int(1)))]
            ))
            views.append(RecordListViewDefinition(
                id: "cancelled", label: "Cancelled", systemImage: "xmark.seal",
                predicates: [ListFilter("docStatus", .eq(.int(2)))]
            ))
        }
        // Distinct workflow statuses present in the data that aren't already
        // covered by the docStatus chips above.
        let covered: Set<String> = ["Draft", "Submitted", "Cancelled"]
        let statuses = Set(documents.map(\.status)).subtracting(covered).filter { !$0.isEmpty }
        for status in statuses.sorted() {
            views.append(RecordListViewDefinition(
                id: "status:\(status)", label: status,
                predicates: [ListFilter("status", .eq(.string(status)))]
            ))
        }
        return views
    }

    private var selectedView: RecordListViewDefinition? {
        viewChips.first { $0.id == selectedViewID }
    }

    private func selectView(_ view: RecordListViewDefinition) {
        selectedViewID = view.id
        if let s = view.searchText { searchText = s }
        if !view.sort.isEmpty, let first = view.sort.first {
            sortFieldKey = first.fieldKey
            sortAscending = first.direction == .ascending
        }
    }

    // MARK: - Field filters

    /// Fields a user can filter on — every declared field except table/image/
    /// attachment/formula which have no meaningful list predicate.
    private var filterableFields: [FieldDefinition] {
        docType.fields.filter { f in
            switch f.type {
            case .table, .image, .attachment, .formula, .richText: return false
            default: return true
            }
        }
    }

    private func applyFieldFilter(field: FieldDefinition, predicate: ListFilter, display: String) {
        // One active filter per field key — re-adding replaces.
        fieldFilters.removeAll { $0.fieldKey == field.key }
        fieldFilters.append(ActiveFieldFilter(fieldKey: field.key, display: display, predicate: predicate))
    }

    private func clearAllFilters() {
        fieldFilters.removeAll()
        searchText = ""
        selectedViewID = "all"
    }

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    private var activeFilterCount: Int {
        var count = fieldFilters.count
        if selectedViewID != "all" { count += 1 }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        return count
    }

    // MARK: - Sorting

    private struct SortOption {
        let label: String
        let fieldKey: String
        let defaultAscending: Bool
    }

    private var sortOptions: [SortOption] {
        var options: [SortOption] = [
            SortOption(label: "Updated", fieldKey: "updatedAt", defaultAscending: false),
            SortOption(label: "Created", fieldKey: "createdAt", defaultAscending: false),
            SortOption(label: "Title", fieldKey: docType.titleField, defaultAscending: true),
            SortOption(label: "Status", fieldKey: "status", defaultAscending: true)
        ]
        // Searchable / indexed fields make good sort keys too.
        let extraKeys = Set(docType.searchFields).union(docType.indexes.map(\.fieldKey))
        for key in extraKeys where key != docType.titleField {
            if let f = docType.fields.first(where: { $0.key == key }) {
                options.append(SortOption(label: f.label, fieldKey: key, defaultAscending: true))
            }
        }
        return options
    }

    private var currentSortLabel: String {
        let base = sortOptions.first { $0.fieldKey == sortFieldKey }?.label ?? "Updated"
        return base
    }

    private var activeSort: [ListSort] {
        [ListSort(fieldKey: sortFieldKey, direction: sortAscending ? .ascending : .descending)]
    }

    // MARK: - Pipeline

    /// Combined predicate set: selected view + active field filters.
    private var activePredicates: [ListFilter] {
        (selectedView?.predicates ?? []) + fieldFilters.map(\.predicate)
    }

    private var processedDocuments: [Document] {
        let lower = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let predicates = activePredicates

        let filtered = documents.filter { doc in
            guard RecordListFilter.matchesAll(predicates, doc) else { return false }
            guard !lower.isEmpty else { return true }
            return doc.id.lowercased().contains(lower)
                || titleValue(for: doc).lowercased().contains(lower)
                || docType.searchFields.contains(where: { key in
                    displayValue(for: key, in: doc).lowercased().contains(lower)
                })
        }

        return filtered.sorted { RecordListFilter.areInIncreasingOrder($0, $1, by: activeSort) }
    }

    private var resultCountText: String {
        let shown = processedDocuments.count
        let total = documents.count
        if shown == total {
            return "\(total) record\(total == 1 ? "" : "s")"
        }
        return "\(shown) of \(total) records"
    }

    private func titleValue(for doc: Document) -> String {
        displayValue(for: docType.titleField, in: doc)
    }

    private func displayValue(for key: String, in doc: Document) -> String {
        let fieldType = docType.fields.first(where: { $0.key == key })?.type
        switch doc.fields[key] {
        case .string(let s):
            if fieldType == .image {
                return s.isEmpty ? "—" : "<image>"
            }
            let value: String
            switch fieldType {
            case .richText?:
                value = plainText(fromMarkdown: s)
            default:
                value = s
            }
            return value.isEmpty ? "—" : value
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "Yes" : "No"
        case .date(let d), .dateTime(let d): return ISO8601DateFormatter().string(from: d)
        case .data(let d):
            return fieldType == .image ? "<image>" : "<\(d.count) bytes>"
        case .array(let xs): return "[\(xs.count) items]"
        case .null, nil: return "—"
        }
    }

    private func plainText(fromMarkdown markdown: String) -> String {
        let characters = ((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)).characters
        return characters
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    private func statusBadge(for status: String) -> some View {
        Text(status.isEmpty ? "Draft" : status)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MercantisTheme.primary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func symbol(for type: FieldType) -> String {
        switch type {
        case .link: return "link"
        case .date, .datetime: return "calendar"
        case .boolean: return "checkmark.square"
        case .select, .status: return "list.bullet"
        case .number, .decimal, .currency: return "number"
        default: return "textformat"
        }
    }

    // MARK: - Persistence

    private var viewStorageKey: String? { preferenceKey.map { "recordList.\($0).view" } }
    private var sortStorageKey: String? { preferenceKey.map { "recordList.\($0).sort" } }

    private func restorePreferencesOnce() {
        guard !didRestore else { return }
        didRestore = true
        if let key = viewStorageKey,
           let saved = UserDefaults.standard.string(forKey: key),
           viewChips.contains(where: { $0.id == saved }) {
            selectedViewID = saved
        }
        if let key = sortStorageKey,
           let raw = UserDefaults.standard.string(forKey: key) {
            // Stored as "fieldKey|asc" / "fieldKey|desc".
            let parts = raw.split(separator: "|")
            if let first = parts.first { sortFieldKey = String(first) }
            sortAscending = parts.count > 1 && parts[1] == "asc"
        }
    }

    private func persistPreferences() {
        guard didRestore else { return }
        if let key = viewStorageKey {
            UserDefaults.standard.set(selectedViewID, forKey: key)
        }
        if let key = sortStorageKey {
            UserDefaults.standard.set("\(sortFieldKey)|\(sortAscending ? "asc" : "desc")", forKey: key)
        }
    }
}

/// An active, user-applied field filter shown as a removable chip.
private struct ActiveFieldFilter: Identifiable {
    let id = UUID()
    let fieldKey: String
    let display: String
    let predicate: ListFilter
}
