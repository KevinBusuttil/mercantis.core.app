import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct RecordCollectionHostView: View {
    let preferenceKey: String
    let docType: DocType
    let workspaceTitle: String
    let workspaceSubtitle: String?
    let workspaceSymbol: String
    let workspaceStatusText: String?
    let documents: [Document]
    let configuration: RecordCollectionViewConfiguration
    let allowsDetailEditing: Bool
    let primaryCreateActionTitle: String
    let onCreateDocument: (() -> Document?)?
    let workspaceOverflowMenu: (() -> AnyView)?
    /// Persists `document` and returns the refreshed copy (e.g. after a
    /// refetch so the caller sees the new `updatedAt`). Returning `nil`
    /// means "don't refresh the host's local copy" — useful for callers
    /// that intentionally manage their own state.
    let onSaveDocument: ((Document) throws -> Document?)?
    /// Deletes `document` from the underlying store. The host clears its
    /// selection after a successful delete; the caller is responsible for
    /// reloading the `documents` collection it passes in.
    let onDeleteDocument: ((Document) throws -> Void)?
    /// End-user-authored fields layered on top of `docType`. The host
    /// merges them into a single composed DocType before rendering the
    /// list and form, so consumers don't need to do the merge themselves.
    let customFields: [CustomField]
    /// Persists a new custom field. When all three customize callbacks are
    /// provided, a "Customize" toolbar button surfaces a sheet that lets
    /// end users add / edit / remove fields without touching the base
    /// DocType definition.
    let onAddCustomField: ((CustomField) throws -> Void)?
    let onUpdateCustomField: ((CustomField) throws -> Void)?
    let onRemoveCustomField: ((String) throws -> Void)?
    let initialSelectedDocumentID: String?
    let onSelectionChange: ((Document?) -> Void)?
    let detailHeader: ((Document) -> AnyView)?
    let externalCreateTrigger: Binding<Bool>?
    let linkSearchProvider: ((String, String) -> [Document])?
    let linkResolveProvider: ((String, String) -> Document?)?
    let childDocTypeProvider: ((String) -> DocType?)?
    let detailEditor: ((DocType, Binding<Document>) -> AnyView)?
    /// Optional built-in / saved list views (e.g. Hub's "Unpaid", "Overdue").
    /// When empty the list synthesises status chips from the loaded data.
    let listViews: [RecordListViewDefinition]
    /// Host-injected business-wording layer forwarded to the list so row
    /// badges / status chips show document-specific labels. Defaults to
    /// `.passthrough` (raw status strings).
    let displayPolicy: DocumentDisplayPolicy

    @State private var selectedDocument: Document?
    @State private var selectedDocumentID: String?
    @State private var selectedViewMode: RecordViewMode
    @State private var createSheetDraft: Document?
    @State private var detailSaveError: String?
    @State private var lastSavedAt: Date?
    @State private var lastSavedID: String?
    @State private var pendingDeleteDocument: Document?
    @State private var showCustomizeSheet = false

    public init(
        preferenceKey: String,
        docType: DocType,
        workspaceTitle: String? = nil,
        workspaceSubtitle: String? = nil,
        workspaceSymbol: String? = nil,
        workspaceStatusText: String? = nil,
        documents: [Document],
        configuration: RecordCollectionViewConfiguration = RecordCollectionViewConfiguration(),
        allowsDetailEditing: Bool = true,
        primaryCreateActionTitle: String = "New",
        onCreateDocument: (() -> Document?)? = nil,
        workspaceOverflowMenu: (() -> AnyView)? = nil,
        onSaveDocument: ((Document) throws -> Document?)? = nil,
        onDeleteDocument: ((Document) throws -> Void)? = nil,
        customFields: [CustomField] = [],
        onAddCustomField: ((CustomField) throws -> Void)? = nil,
        onUpdateCustomField: ((CustomField) throws -> Void)? = nil,
        onRemoveCustomField: ((String) throws -> Void)? = nil,
        initialSelectedDocumentID: String? = nil,
        onSelectionChange: ((Document?) -> Void)? = nil,
        detailHeader: ((Document) -> AnyView)? = nil,
        externalCreateTrigger: Binding<Bool>? = nil,
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        linkResolveProvider: ((String, String) -> Document?)? = nil,
        childDocTypeProvider: ((String) -> DocType?)? = nil,
        detailEditor: ((DocType, Binding<Document>) -> AnyView)? = nil,
        listViews: [RecordListViewDefinition] = [],
        displayPolicy: DocumentDisplayPolicy = .passthrough
    ) {
        self.preferenceKey = preferenceKey
        self.docType = docType
        self.workspaceTitle = workspaceTitle ?? docType.name
        self.workspaceSubtitle = workspaceSubtitle
        self.workspaceSymbol = workspaceSymbol ?? "rectangle.stack"
        self.workspaceStatusText = workspaceStatusText
        self.documents = documents
        self.configuration = configuration
        self.allowsDetailEditing = allowsDetailEditing
        self.primaryCreateActionTitle = primaryCreateActionTitle
        self.onCreateDocument = onCreateDocument
        self.workspaceOverflowMenu = workspaceOverflowMenu
        self.onSaveDocument = onSaveDocument
        self.onDeleteDocument = onDeleteDocument
        self.customFields = customFields
        self.onAddCustomField = onAddCustomField
        self.onUpdateCustomField = onUpdateCustomField
        self.onRemoveCustomField = onRemoveCustomField
        self.initialSelectedDocumentID = initialSelectedDocumentID
        self.onSelectionChange = onSelectionChange
        self.detailHeader = detailHeader
        self.externalCreateTrigger = externalCreateTrigger
        self.linkSearchProvider = linkSearchProvider
        self.linkResolveProvider = linkResolveProvider
        self.childDocTypeProvider = childDocTypeProvider
        self.detailEditor = detailEditor
        self.listViews = listViews
        self.displayPolicy = displayPolicy
        _selectedViewMode = State(initialValue: configuration.defaultViewMode)
    }

    public var body: some View {
        VStack(spacing: 0) {
            heroHeader
            contentPane
        }
        .navigationTitle(workspaceTitle)
        .toolbar(content: workspaceToolbar)
        .sheet(item: $createSheetDraft) { _ in
            CreateRecordSheet(
                docType: effectiveDocType,
                draft: Binding(
                    get: { createSheetDraft ?? emptyDocument(for: docType.id) },
                    set: { createSheetDraft = $0 }
                ),
                onCreate: performCreate(_:),
                linkSearchProvider: linkSearchProvider,
                linkResolveProvider: linkResolveProvider,
                childDocTypeProvider: childDocTypeProvider
            )
        }
        .onAppear {
            restorePersistedViewMode()
            syncSelection(from: initialSelectedDocumentID)
            if externalCreateTrigger?.wrappedValue == true {
                consumeExternalCreateTrigger()
            }
        }
        .onChange(of: selectedViewMode) { _, mode in
            persistViewMode(mode)
        }
        .onChange(of: documentIDs) { _, _ in
            syncSelection(from: selectedDocumentID ?? initialSelectedDocumentID)
        }
        .onChange(of: initialSelectedDocumentID) { _, selectedId in
            syncSelection(from: selectedId)
        }
        .onChange(of: externalCreateTrigger?.wrappedValue ?? false) { _, requested in
            if requested { consumeExternalCreateTrigger() }
        }
        .confirmationDialog(
            "Delete this \(docType.name)?",
            isPresented: pendingDeleteBinding,
            titleVisibility: .visible,
            presenting: pendingDeleteDocument
        ) { document in
            Button("Delete \(docType.name)", role: .destructive) {
                performDelete(document)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteDocument = nil
            }
        } message: { document in
            Text("This will permanently remove \(document.id.isEmpty ? "this draft" : document.id). This action cannot be undone.")
        }
        .sheet(isPresented: $showCustomizeSheet) {
            if canCustomizeFields {
                // `effectiveDocType.fields` is base + custom so the Position
                // picker lets users place a new field after either a built-in
                // field or one of their own additions.
                CustomizeWorkspaceSheet(
                    docTypeName: docType.name,
                    baseFields: effectiveDocType.fields.map {
                        CustomizeWorkspaceSheet.BaseFieldEntry(key: $0.key, label: $0.label)
                    },
                    customFields: customFields,
                    onAdd: onAddCustomField ?? { _ in },
                    onUpdate: onUpdateCustomField ?? { _ in },
                    onRemove: onRemoveCustomField ?? { _ in }
                )
            }
        }
    }

    /// All three customize callbacks must be supplied to enable the
    /// in-app editor. A consumer that wants read-only custom fields can
    /// pass `customFields` without any of the callbacks.
    private var canCustomizeFields: Bool {
        onAddCustomField != nil
            && onUpdateCustomField != nil
            && onRemoveCustomField != nil
    }

    /// `docType` with any persisted custom fields merged in at their
    /// declared `insertAfter` positions. Used wherever the host renders
    /// the form / list so end-user fields show up natively.
    private var effectiveDocType: DocType {
        Self.merge(base: docType, customFields: customFields)
    }

    private static func merge(base: DocType, customFields: [CustomField]) -> DocType {
        guard !customFields.isEmpty else { return base }
        var composed = base
        var fields = composed.fields
        for cf in customFields {
            let new = cf.fieldDefinition
            if let after = cf.insertAfter, !after.isEmpty,
               let idx = fields.firstIndex(where: { $0.key == after }) {
                fields.insert(new, at: fields.index(after: idx))
            } else {
                fields.append(new)
            }
        }
        composed.fields = fields
        return composed
    }

    private var pendingDeleteBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingDeleteDocument != nil },
            set: { newValue in
                if !newValue { pendingDeleteDocument = nil }
            }
        )
    }

    private var heroHeader: some View {
        WorkspaceHeroHeader(
            symbol: workspaceSymbol,
            title: workspaceTitle,
            subtitle: workspaceSubtitle,
            badges: heroBadges,
            primaryActionTitle: createDocumentAction != nil ? primaryCreateActionTitle : nil,
            primaryAction: createDocumentAction
        )
    }

    private var heroBadges: [WorkspaceHeroHeader.Badge] {
        var badges: [WorkspaceHeroHeader.Badge] = [
            .init("\(documents.count) records")
        ]
        if !docType.module.isEmpty {
            badges.append(.init(docType.module, tone: .info))
        }
        return badges
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selectedViewMode {
        case .list:
            listPane
        case .browse:
            browsePane
        case .detail:
            detailPane
        }
    }

    private func workspaceToolbar() -> RecordWorkspaceToolbarContent {
        RecordWorkspaceToolbarContent(
            statusText: workspaceRecordStatusText,
            selectedViewMode: $selectedViewMode,
            supportedViewModes: configuration.supportedViewModes,
            primaryActionTitle: primaryCreateActionTitle,
            // Primary create lives in the hero header; surfacing it here too
            // would render two identical "+ New <DocType>" buttons on every
            // workspace.
            onPrimaryAction: nil,
            onCustomizeFields: canCustomizeFields
                ? { showCustomizeSheet = true }
                : nil,
            overflowMenuContent: workspaceOverflowMenu
        )
    }

    private var listPane: some View {
        GenericListView(
            docType: effectiveDocType,
            documents: documents,
            selectedDocumentID: selectedDocument?.id,
            onSelect: selectDocument(_:),
            onCreate: handleCreateDocument,
            listViews: listViews,
            preferenceKey: preferenceKey,
            linkSearchProvider: linkSearchProvider,
            linkResolveProvider: linkResolveProvider,
            linkTargetMetaProvider: childDocTypeProvider,
            displayPolicy: displayPolicy
        )
    }

    private var browsePane: some View {
        HStack(spacing: 0) {
            listPane
                .frame(minWidth: 400, maxWidth: .infinity)

            Divider()

            detailPane
                .frame(minWidth: 380, maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if selectedDocument != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let selectedDocument, let detailHeader {
                    detailHeader(selectedDocument)
                }

                if let detailEditor {
                    detailEditor(effectiveDocType, selectedDocumentBinding)
                } else {
                    GenericFormView(
                        docType: effectiveDocType,
                        document: selectedDocumentBinding,
                        linkSearchProvider: linkSearchProvider,
                        linkResolveProvider: linkResolveProvider,
                        childDocTypeProvider: childDocTypeProvider
                    )
                    .disabled(!allowsDetailEditing)
                }

                if let detailSaveError {
                    Text(detailSaveError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MercantisTheme.danger)
                        .padding(10)
                        .background(MercantisTheme.fillSoft(for: .danger), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                persistenceFooter
            }
        } else {
            ContentUnavailableView("Select a record to view details", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Unified Save + Delete footer, plus a "Saved · just now" indicator.
    /// Shown in the detail pane so it works for both the default
    /// `GenericFormView` editor and any custom `detailEditor` a caller
    /// supplies. The Save flow refreshes `selectedDocument` from the
    /// caller's return value so optimistic-concurrency timestamps stay
    /// fresh between consecutive saves.
    @ViewBuilder
    private var persistenceFooter: some View {
        if onSaveDocument != nil || canDeleteSelected {
            HStack(spacing: 10) {
                savedIndicator
                Spacer()
                if onSaveDocument != nil {
                    Button("Save") { performSave() }
                        .buttonStyle(MercantisPrimaryButtonStyle())
                        .keyboardShortcut("s", modifiers: [.command])
                        .disabled(selectedDocument == nil)
                }
                if canDeleteSelected {
                    Button(role: .destructive) {
                        pendingDeleteDocument = selectedDocument
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var savedIndicator: some View {
        if let lastSavedAt {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MercantisTheme.success)
                Text("Saved \(Self.relativeSaved(lastSavedAt))")
                    .foregroundStyle(.secondary)
                if let lastSavedID, !lastSavedID.isEmpty {
                    Text("· \(lastSavedID)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
        }
    }

    private static func relativeSaved(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 2 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Delete is offered for persisted records that aren't currently
    /// Submitted (docStatus 1). `DocumentEngine.delete` also enforces this,
    /// but we hide the affordance up front so users don't see a button that
    /// always errors.
    private var canDeleteSelected: Bool {
        guard onDeleteDocument != nil else { return false }
        guard let selectedDocument else { return false }
        return !selectedDocument.id.isEmpty && selectedDocument.docStatus != 1
    }

    private func performSave() {
        guard let onSaveDocument, let selectedDocument else { return }
        do {
            let refreshed = try onSaveDocument(selectedDocument)
            if let refreshed {
                self.selectedDocument = refreshed
                self.selectedDocumentID = refreshed.id
                onSelectionChange?(refreshed)
            }
            lastSavedAt = Date()
            lastSavedID = refreshed?.id ?? selectedDocument.id
            detailSaveError = nil
        } catch {
            detailSaveError = (error as NSError).localizedDescription
        }
    }

    private func performDelete(_ document: Document) {
        guard let onDeleteDocument else { return }
        do {
            try onDeleteDocument(document)
            // Drop the cached selection up front; the host's onChange of
            // `documentIDs` will then re-evaluate selection against the
            // refreshed `documents` array.
            selectedDocument = nil
            selectedDocumentID = nil
            onSelectionChange?(nil)
            detailSaveError = nil
            lastSavedAt = nil
            lastSavedID = nil
            pendingDeleteDocument = nil
        } catch {
            detailSaveError = (error as NSError).localizedDescription
            pendingDeleteDocument = nil
        }
    }

    private var selectedDocumentBinding: Binding<Document> {
        Binding<Document>(
            get: {
                selectedDocument ?? emptyDocument(for: docType.id)
            },
            set: { updated in
                selectedDocument = updated
                selectedDocumentID = updated.id
                onSelectionChange?(updated)
            }
        )
    }

    private var viewModeStorageKey: String {
        "recordViewMode.\(preferenceKey)"
    }

    private var workspaceRecordStatusText: String {
        workspaceStatusText ?? "\(documents.count) records"
    }

    private var createDocumentAction: (() -> Void)? {
        guard onCreateDocument != nil else { return nil }
        return handleCreateDocument
    }

    private var documentIDs: [String] {
        documents.map(\.id)
    }

    private func selectDocument(_ document: Document) {
        selectedDocument = document
        selectedDocumentID = document.id
        onSelectionChange?(document)
    }

    private func handleCreateDocument() {
        // Parents (e.g. `DocTypeListView`) return nil from `onCreateDocument`
        // when they present their own bespoke sheet (`DocTypeBuilderView`).
        // In that case, `onCreateDocument` has already triggered the sheet as a
        // side-effect and we simply short-circuit here.
        guard let draft = onCreateDocument?() else { return }
        createSheetDraft = draft
    }

    private func consumeExternalCreateTrigger() {
        guard let externalCreateTrigger else { return }
        handleCreateDocument()
        externalCreateTrigger.wrappedValue = false
    }

    private func performCreate(_ draft: Document) throws {
        let saved = try onSaveDocument?(draft)
        // Use the engine's assigned id (naming series may have rewritten it)
        // so `onChange(of: documentIDs)` reselects the right row when the
        // refreshed `documents` array arrives.
        selectedDocumentID = saved?.id ?? draft.id
        if let saved {
            selectedDocument = saved
            onSelectionChange?(saved)
            lastSavedAt = Date()
            lastSavedID = saved.id
        }
    }

    private func syncSelection(from documentID: String?) {
        if !configuration.supportedViewModes.contains(selectedViewMode) {
            selectedViewMode = configuration.defaultViewMode
        }

        if shouldPreserveTransientSelection(incomingDocumentID: documentID) {
            return
        }

        if let documentID,
           let matching = documents.first(where: { $0.id == documentID }) {
            selectDocument(matching)
            return
        }

        if let selectedDocumentID,
           let matching = documents.first(where: { $0.id == selectedDocumentID }) {
            selectDocument(matching)
            return
        }

        if selectedViewMode == .browse || selectedViewMode == .detail,
           let first = documents.first {
            selectDocument(first)
            return
        }

        selectedDocument = nil
        selectedDocumentID = nil
        onSelectionChange?(nil)
    }

    private func restorePersistedViewMode() {
        guard let rawValue = UserDefaults.standard.string(forKey: viewModeStorageKey),
              let mode = RecordViewMode(rawValue: rawValue),
              configuration.supportedViewModes.contains(mode) else {
            selectedViewMode = configuration.defaultViewMode
            return
        }
        selectedViewMode = mode
    }

    private func persistViewMode(_ mode: RecordViewMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: viewModeStorageKey)
    }

    private func shouldPreserveTransientSelection(incomingDocumentID: String?) -> Bool {
        guard let selectedDocument else { return false }
        let selectionExistsInDocuments = documents.contains(where: { $0.id == selectedDocument.id })
        guard !selectionExistsInDocuments else { return false }
        return incomingDocumentID == nil || incomingDocumentID == selectedDocument.id
    }

    private func emptyDocument(for docTypeId: String) -> Document {
        let now = Date()
        return Document(
            id: UUID().uuidString,
            docType: docTypeId,
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
}
