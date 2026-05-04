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
    let onSaveDocument: ((Document) throws -> Void)?
    let initialSelectedDocumentID: String?
    let onSelectionChange: ((Document?) -> Void)?
    let detailHeader: ((Document) -> AnyView)?
    let externalCreateTrigger: Binding<Bool>?

    @State private var selectedDocument: Document?
    @State private var selectedDocumentID: String?
    @State private var selectedViewMode: RecordViewMode
    @State private var createSheetDraft: Document?
    @State private var detailSaveError: String?

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
        onSaveDocument: ((Document) throws -> Void)? = nil,
        initialSelectedDocumentID: String? = nil,
        onSelectionChange: ((Document?) -> Void)? = nil,
        detailHeader: ((Document) -> AnyView)? = nil,
        externalCreateTrigger: Binding<Bool>? = nil
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
        self.initialSelectedDocumentID = initialSelectedDocumentID
        self.onSelectionChange = onSelectionChange
        self.detailHeader = detailHeader
        self.externalCreateTrigger = externalCreateTrigger
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
                docType: docType,
                draft: Binding(
                    get: { createSheetDraft ?? emptyDocument(for: docType.id) },
                    set: { createSheetDraft = $0 }
                ),
                onCreate: performCreate(_:)
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
            onPrimaryAction: createDocumentAction,
            overflowMenuContent: workspaceOverflowMenu
        )
    }

    private var listPane: some View {
        GenericListView(
            docType: docType,
            documents: documents,
            onSelect: selectDocument(_:),
            onCreate: handleCreateDocument
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

                GenericFormView(docType: docType, document: selectedDocumentBinding)
                    .disabled(!allowsDetailEditing)

                if let detailSaveError {
                    Text(detailSaveError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MercantisTheme.danger)
                        .padding(10)
                        .background(MercantisTheme.fillSoft(for: .danger), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

                if let onSaveDocument {
                    HStack {
                        Spacer()
                        Button("Save") {
                            guard let selectedDocument else { return }
                            do {
                                try onSaveDocument(selectedDocument)
                                detailSaveError = nil
                            } catch {
                                detailSaveError = (error as NSError).localizedDescription
                            }
                        }
                        .buttonStyle(MercantisPrimaryButtonStyle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        } else {
            ContentUnavailableView("Select a record to view details", systemImage: "doc.text.magnifyingglass")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        try onSaveDocument?(draft)
        // Queue selection for when the fresh `documents` list re-renders with
        // the new row; `onChange(of: documentIDs)` will pick it up and syncSelection.
        selectedDocumentID = draft.id
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
