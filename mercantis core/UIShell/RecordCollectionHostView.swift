import SwiftUI

public struct RecordCollectionHostView: View {
    let preferenceKey: String
    let docType: DocType
    let workspaceTitle: String
    let workspaceStatusText: String?
    let documents: [Document]
    let configuration: RecordCollectionViewConfiguration
    let allowsDetailEditing: Bool
    let primaryCreateActionTitle: String
    let onCreateDocument: (() -> Document?)?
    let workspaceOverflowMenu: (() -> AnyView)?
    let onSaveDocument: ((Document) -> Void)?
    let initialSelectedDocumentID: String?
    let onSelectionChange: ((Document?) -> Void)?
    let detailHeader: ((Document) -> AnyView)?

    @State private var selectedDocument: Document?
    @State private var selectedDocumentID: String?
    @State private var selectedViewMode: RecordViewMode

    public init(
        preferenceKey: String,
        docType: DocType,
        workspaceTitle: String? = nil,
        workspaceStatusText: String? = nil,
        documents: [Document],
        configuration: RecordCollectionViewConfiguration = RecordCollectionViewConfiguration(),
        allowsDetailEditing: Bool = true,
        primaryCreateActionTitle: String = "New",
        onCreateDocument: (() -> Document?)? = nil,
        workspaceOverflowMenu: (() -> AnyView)? = nil,
        onSaveDocument: ((Document) -> Void)? = nil,
        initialSelectedDocumentID: String? = nil,
        onSelectionChange: ((Document?) -> Void)? = nil,
        detailHeader: ((Document) -> AnyView)? = nil
    ) {
        self.preferenceKey = preferenceKey
        self.docType = docType
        self.workspaceTitle = workspaceTitle ?? docType.name
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
        _selectedViewMode = State(initialValue: configuration.defaultViewMode)
    }

    public var body: some View {
        contentPane
        .navigationTitle(workspaceTitle)
        .toolbar(content: workspaceToolbar)
        .onAppear {
            restorePersistedViewMode()
            syncSelection(from: initialSelectedDocumentID)
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
                        .padding(.horizontal)
                        .padding(.top, 12)
                }

                GenericFormView(docType: docType, document: selectedDocumentBinding)
                    .disabled(!allowsDetailEditing)

                if let onSaveDocument {
                    HStack {
                        Spacer()
                        Button("Save") {
                            if let selectedDocument {
                                onSaveDocument(selectedDocument)
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
        guard let draft = onCreateDocument?() else { return }
        selectDocument(draft)
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
