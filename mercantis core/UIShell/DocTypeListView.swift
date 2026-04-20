import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var selectedDocTypeForBuilder: DocType?
    @State private var selectedDocTypeID: String?
    @State private var showNewDocTypeSheet = false
    @State private var docTypeToDelete: DocType?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var projectedDocTypeDocuments: [Document] = []

    public init() {}

    public var body: some View {
        RecordCollectionHostView(
            preferenceKey: "docType.management",
            docType: BuiltInDocTypes.docType,
            documents: projectedDocTypeDocuments,
            configuration: RecordCollectionViewConfiguration(
                supportedViewModes: [.list, .browse, .detail],
                defaultViewMode: .list
            ),
            allowsDetailEditing: false,
            initialSelectedDocumentID: selectedDocTypeID,
            onSelectionChange: { selected in
                selectedDocTypeID = selected?.id
            },
            detailHeader: { document in
                AnyView(selectedDocTypeHeader(for: document))
            }
        )
        .navigationTitle("DocTypes")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DocTypes")
                    Text("\(tooling.navigableDocTypes.count) registered")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            ToolbarItemGroup(placement: .automatic) {
                Button("New DocType") {
                    showNewDocTypeSheet = true
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
            }
        }
        .onAppear {
            tooling.reload()
            refreshProjectedDocTypeDocuments()
            if selectedDocTypeID == nil {
                selectedDocTypeID = tooling.navigableDocTypes.first?.id
            }
        }
        .onChange(of: tooling.navigableDocTypes.map(\.id)) { _, ids in
            refreshProjectedDocTypeDocuments()
            if let selectedDocTypeID, ids.contains(selectedDocTypeID) {
                return
            }
            self.selectedDocTypeID = ids.first
        }
        .onChange(of: docTypeChangeDetectionSignatures) { _, _ in
            refreshProjectedDocTypeDocuments()
        }
        .sheet(isPresented: $showNewDocTypeSheet) {
            NavigationStack {
                DocTypeBuilderView {
                    tooling.reload()
                }
            }
            .frame(minWidth: 640, idealWidth: 820, minHeight: 520, idealHeight: 680)
            #if os(macOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            .environmentObject(tooling)
        }
        #if !os(macOS)
        .sheet(item: $selectedDocTypeForBuilder) { docType in
            NavigationStack {
                FormBuilderView(initialDocTypeID: docType.id) {
                    tooling.reload()
                    selectedDocTypeID = docType.id
                }
                .navigationTitle("Visual Builder")
            }
            .frame(minWidth: 1000, idealWidth: 1280, minHeight: 620, idealHeight: 760)
            #if os(macOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            .environmentObject(tooling)
        }
        #endif
        .alert(
            "Delete DocType?",
            isPresented: $showDeleteConfirmation,
            presenting: docTypeToDelete
        ) { docType in
            Button("Delete", role: .destructive) {
                do {
                    try tooling.delete(docTypeId: docType.id)
                } catch {
                    deleteErrorMessage = tooling.errorMessage(for: error)
                }
                docTypeToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                docTypeToDelete = nil
            }
        } message: { docType in
            Text("Are you sure you want to delete '\(docType.name)'? This cannot be undone.")
        }
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var docTypeChangeDetectionSignatures: [DocTypeProjectionSignature] {
        tooling.navigableDocTypes.map { docType in
            DocTypeProjectionSignature(
                id: docType.id,
                name: docType.name,
                module: docType.module,
                isSubmittable: docType.isSubmittable,
                isChildTable: docType.isChildTable,
                isCustom: docType.isCustom,
                fieldCount: docType.fields.count,
                permissionCount: docType.permissions.count
            )
        }
    }

    private func refreshProjectedDocTypeDocuments() {
        let now = Date()
        projectedDocTypeDocuments = tooling.navigableDocTypes.map { docType in
            Document(
                id: docType.id,
                docType: BuiltInDocTypes.docType.id,
                company: "",
                status: docType.isCustom ? "Custom" : "Built-in",
                createdAt: now,
                updatedAt: now,
                syncVersion: 0,
                syncState: .local,
                fields: [
                    "name": .string(docType.name),
                    "module": .string(docType.module),
                    "isSubmittable": .bool(docType.isSubmittable),
                    "isChildTable": .bool(docType.isChildTable),
                    "titleField": .string(docType.titleField),
                    "searchFields": .string(docType.searchFields.joined(separator: ", "))
                ],
                children: [
                    "fields": docType.fields.enumerated().map { index, field in
                        ChildRow(
                            id: "\(docType.id).field.\(index)",
                            rowIndex: index,
                            fields: [
                                "key": .string(field.key),
                                "label": .string(field.label),
                                "type": .string(field.type.rawValue),
                                "required": .bool(field.required),
                                "options": .string((field.options ?? []).joined(separator: ", "))
                            ]
                        )
                    },
                    "permissions": docType.permissions.enumerated().map { index, permission in
                        ChildRow(
                            id: "\(docType.id).permission.\(index)",
                            rowIndex: index,
                            fields: [
                                "role": .string(permission.role),
                                "canRead": .bool(permission.canRead),
                                "canWrite": .bool(permission.canWrite),
                                "canCreate": .bool(permission.canCreate),
                                "canDelete": .bool(permission.canDelete),
                                "canSubmit": .bool(permission.canSubmit),
                                "canAmend": .bool(permission.canAmend)
                            ]
                        )
                    }
                ]
            )
        }
    }

    private func openVisualBuilder(for docType: DocType) {
        #if os(macOS)
        openWindow(id: mercantis_coreApp.visualBuilderWindowID, value: docType.id)
        #else
        selectedDocTypeForBuilder = docType
        #endif
    }

    @ViewBuilder
    private func selectedDocTypeHeader(for document: Document) -> some View {
        if let docType = tooling.navigableDocTypes.first(where: { $0.id == document.id }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(docType.name)
                        .font(.headline)

                    Text(docType.module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }

                Spacer()

                Button("Open Visual Builder") {
                    openVisualBuilder(for: docType)
                }
                .buttonStyle(MercantisSecondaryButtonStyle())

                Menu {
                    Button("Delete DocType", role: .destructive) {
                        docTypeToDelete = docType
                        showDeleteConfirmation = true
                    }
                    .disabled(!docType.isCustom)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .accessibilityLabel("More actions")
                }
                .menuStyle(.borderlessButton)
                .help("More actions")
            }
        }
    }
}

private struct DocTypeProjectionSignature: Hashable {
    let id: String
    let name: String
    let module: String
    let isSubmittable: Bool
    let isChildTable: Bool
    let isCustom: Bool
    let fieldCount: Int
    let permissionCount: Int

}
