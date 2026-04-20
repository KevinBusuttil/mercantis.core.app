import SwiftUI

public struct RecordCollectionHostView: View {
    let preferenceKey: String
    let docType: DocType
    let documents: [Document]
    let configuration: RecordCollectionViewConfiguration
    let allowsDetailEditing: Bool
    let onCreateDocument: (() -> Document?)?
    let onSaveDocument: ((Document) -> Void)?
    let initialSelectedDocumentID: String?
    let onSelectionChange: ((Document?) -> Void)?

    @State private var selectedDocument: Document?
    @State private var selectedDocumentID: String?
    @State private var selectedViewMode: RecordViewMode

    public init(
        preferenceKey: String,
        docType: DocType,
        documents: [Document],
        configuration: RecordCollectionViewConfiguration = RecordCollectionViewConfiguration(),
        allowsDetailEditing: Bool = true,
        onCreateDocument: (() -> Document?)? = nil,
        onSaveDocument: ((Document) -> Void)? = nil,
        initialSelectedDocumentID: String? = nil,
        onSelectionChange: ((Document?) -> Void)? = nil
    ) {
        self.preferenceKey = preferenceKey
        self.docType = docType
        self.documents = documents
        self.configuration = configuration
        self.allowsDetailEditing = allowsDetailEditing
        self.onCreateDocument = onCreateDocument
        self.onSaveDocument = onSaveDocument
        self.initialSelectedDocumentID = initialSelectedDocumentID
        self.onSelectionChange = onSelectionChange
        _selectedViewMode = State(initialValue: configuration.defaultViewMode)
    }

    public var body: some View {
        Group {
            switch selectedViewMode {
            case .list:
                listPane
            case .browse:
                browsePane
            case .detail:
                detailPane
            }
        }
        .navigationTitle(docType.name)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Record View Mode", selection: $selectedViewMode) {
                    ForEach(configuration.supportedViewModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 220)
                .accessibilityLabel("Record View Mode")
            }
        }
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

        if let selectedDocument,
           documents.contains(where: { $0.id == selectedDocument.id }) == false,
           documentID == nil || documentID == selectedDocument.id {
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
