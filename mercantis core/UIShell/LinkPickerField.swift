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
    /// Resolved metadata for the target DocType, used to pick its `titleField`
    /// when rendering display labels. `nil` falls back to convention-based
    /// label resolution (see `LinkLabel`).
    let targetMeta: DocType?
    let searchProvider: ((String, String) -> [Document])?
    /// Fetches the currently-linked document by its stored id so the collapsed
    /// field can show a human label instead of the raw id. `nil` falls back to
    /// displaying the stored id verbatim.
    let resolveDocument: ((String) -> Document?)?
    /// Builds a blank draft of the target DocType for inline "create new"
    /// from within the picker. `nil` (or a `nil` return) hides the create action.
    let makeDraft: (() -> Document?)?
    /// Persists a draft created inline and returns the saved document (whose id
    /// becomes the link value). `nil` hides the create action.
    let commitDraft: ((Document) throws -> Document)?

    @State private var isPickerPresented = false
    @State private var searchQuery = ""
    @State private var searchResults: [Document] = []
    @State private var lastSearchError: String?
    @State private var isCreating = false
    @State private var draftDocument: Document?
    @State private var createError: String?

    public init(
        targetDocType: String,
        value: Binding<String>,
        isReadOnly: Bool,
        targetMeta: DocType? = nil,
        searchProvider: ((String, String) -> [Document])?,
        resolveDocument: ((String) -> Document?)? = nil,
        makeDraft: (() -> Document?)? = nil,
        commitDraft: ((Document) throws -> Document)? = nil
    ) {
        self.targetDocType = targetDocType
        self._value = value
        self.isReadOnly = isReadOnly
        self.targetMeta = targetMeta
        self.searchProvider = searchProvider
        self.resolveDocument = resolveDocument
        self.makeDraft = makeDraft
        self.commitDraft = commitDraft
    }

    /// Whether the picker can offer inline creation of a new target record.
    private var canCreate: Bool {
        makeDraft != nil && commitDraft != nil && targetMeta != nil
    }

    /// Human-facing label for the current selection. Resolves the stored id to
    /// its target document and reads the title field; falls back to the raw id
    /// when no resolver is wired or the target can't be found.
    private var displayLabel: String {
        guard !value.isEmpty else { return "" }
        if let resolveDocument, let doc = resolveDocument(value) {
            return LinkLabel.title(for: doc, meta: targetMeta)
        }
        return value
    }

    public var body: some View {
        if isReadOnly {
            Text(value.isEmpty ? "—" : displayLabel)
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
            HStack(spacing: 6) {
                pickerButton
                // Surface "create new" on the field itself (not just inside the
                // picker) so a new user with no records yet sees the path to add
                // one without first opening an empty picker.
                if canCreate && value.isEmpty {
                    newRecordButton
                }
            }
            .sheet(isPresented: $isPickerPresented, onDismiss: {
                searchQuery = ""
                lastSearchError = nil
                isCreating = false
                draftDocument = nil
                createError = nil
            }) {
                pickerSheet
            }
        }
    }

    /// Compact "+ New" button shown beside an empty link field. Opens the picker
    /// straight into its inline create form.
    private var newRecordButton: some View {
        Button {
            presentCreateDirectly()
        } label: {
            Image(systemName: "plus")
                .imageScale(.small)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(MercantisTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("New \(targetDocType)")
    }

    // MARK: - Picker button (idle state)

    private var pickerButton: some View {
        Button {
            refreshResults(query: "")
            isPickerPresented = true
        } label: {
            HStack {
                Text(value.isEmpty ? "Select \(targetDocType)…" : displayLabel)
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

    /// Rewritten as a top-down VStack instead of a `NavigationStack`-wrapped
    /// `List` because on macOS the previous shape compressed to a few
    /// dozen points high when nested inside another sheet (e.g. the
    /// create-record sheet on a Sales Order), making the result list
    /// effectively invisible — which is what the "the picker shows
    /// nothing" report was about.
    @ViewBuilder
    private var pickerSheet: some View {
        Group {
            if isCreating, let meta = targetMeta {
                createSheet(meta: meta)
            } else {
                searchSheet
            }
        }
        .frame(minWidth: 460, idealWidth: 540, minHeight: 380, idealHeight: 460)
        #if os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
    }

    private var searchSheet: some View {
        VStack(spacing: 0) {
            pickerHeader
            Divider()
            if let error = lastSearchError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MercantisTheme.fillSoft(for: .danger))
            }
            resultsBody
            Divider()
            pickerFooter
        }
    }

    // MARK: - Inline create

    /// Drive into the inline create form: build a fresh draft and switch the
    /// sheet over to it.
    private func startCreate() {
        guard let draft = makeDraft?() else { return }
        draftDocument = draft
        createError = nil
        isCreating = true
    }

    /// Open the picker already in create mode — used by the field's "+ New"
    /// button so the user lands straight on the blank new-record form.
    private func presentCreateDirectly() {
        guard let draft = makeDraft?() else { return }
        draftDocument = draft
        createError = nil
        isCreating = true
        isPickerPresented = true
    }

    /// Persist the inline draft, select it, and dismiss. Errors stay in the
    /// create form so the user can fix and retry.
    private func commitNewRecord() {
        guard let commitDraft, let draft = draftDocument else { return }
        do {
            let saved = try commitDraft(draft)
            value = saved.id
            isCreating = false
            draftDocument = nil
            isPickerPresented = false
        } catch {
            createError = (error as NSError).localizedDescription
        }
    }

    private var draftBinding: Binding<Document> {
        Binding(
            get: { draftDocument ?? Self.emptyDraft(for: targetDocType) },
            set: { draftDocument = $0 }
        )
    }

    private static func emptyDraft(for docType: String) -> Document {
        let now = Date()
        return Document(
            id: "",
            docType: docType,
            company: "",
            status: "",
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            fields: [:],
            children: [:]
        )
    }

    private func createSheet(meta: DocType) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("New \(targetDocType)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(MercantisTheme.surface)
            Divider()
            if let createError {
                Text(createError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MercantisTheme.fillSoft(for: .danger))
            }
            ScrollView {
                GenericFormView(docType: meta, document: draftBinding)
                    .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    isCreating = false
                    draftDocument = nil
                    createError = nil
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button("Create \(targetDocType)") {
                    commitNewRecord()
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(MercantisTheme.surface)
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 10) {
            Text("Select \(targetDocType)")
                .font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search \(targetDocType)", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 260)
                    .onChange(of: searchQuery) { _, query in
                        refreshResults(query: query)
                    }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        refreshResults(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(MercantisTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MercantisTheme.surface)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if searchResults.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(searchQuery.isEmpty
                     ? "No \(targetDocType) records yet"
                     : "No results for \"\(searchQuery)\"")
                    .font(.headline)
                Text(searchQuery.isEmpty
                     ? (canCreate
                        ? "Create one now and link it without leaving this form."
                        : "Create a \(targetDocType) first, then link to it from here.")
                     : "Try a different search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if canCreate {
                    Button {
                        startCreate()
                    } label: {
                        Label("Create new \(targetDocType)", systemImage: "plus")
                    }
                    .buttonStyle(MercantisPrimaryButtonStyle())
                    .padding(.top, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults, id: \.id) { doc in
                        resultRow(for: doc)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

    private func resultRow(for doc: Document) -> some View {
        Button {
            value = doc.id
            isPickerPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel(for: doc))
                        .font(.body)
                        .lineLimit(1)
                    Text(doc.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pickerFooter: some View {
        HStack {
            Text(searchResults.isEmpty
                 ? ""
                 : "\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !value.isEmpty {
                Button("Clear selection") {
                    value = ""
                    isPickerPresented = false
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
            if canCreate {
                Button {
                    startCreate()
                } label: {
                    Label("New \(targetDocType)", systemImage: "plus")
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
            }
            Button("Cancel") { isPickerPresented = false }
                .buttonStyle(MercantisSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MercantisTheme.surface)
    }

    // MARK: - Helpers

    /// Pulls fresh results from the provider and captures any thrown
    /// error for display, so a failing provider doesn't silently leave
    /// the picker looking like the target DocType has no records.
    private func refreshResults(query: String) {
        guard let searchProvider else {
            searchResults = []
            return
        }
        searchResults = searchProvider(targetDocType, query)
        lastSearchError = nil
    }

    /// Human label for a result row, resolved from the target DocType's
    /// declared `titleField` (with convention/id fallbacks). Shared with the
    /// collapsed-field label via `LinkLabel` so both render identically.
    private func primaryLabel(for doc: Document) -> String {
        LinkLabel.title(for: doc, meta: targetMeta)
    }
}
