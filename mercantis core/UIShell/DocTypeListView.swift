import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    @EnvironmentObject private var router: UIShellRouter
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
            workspaceTitle: "DocTypes",
            workspaceStatusText: "\(tooling.navigableDocTypes.count) registered",
            documents: projectedDocTypeDocuments,
            configuration: RecordCollectionViewConfiguration(
                supportedViewModes: [.list, .browse, .detail],
                defaultViewMode: .list
            ),
            allowsDetailEditing: false,
            onCreateDocument: {
                // DocType metadata is authored in `DocTypeBuilderView`, not the
                // generic form. Returning nil short-circuits the host's sheet and
                // lets our bespoke sheet below take over.
                showNewDocTypeSheet = true
                return nil
            },
            initialSelectedDocumentID: selectedDocTypeID,
            onSelectionChange: { selected in
                selectedDocTypeID = selected?.id
            },
            detailHeader: { document in
                AnyView(selectedDocTypeHeader(for: document))
            },
            externalCreateTrigger: Binding<Bool>(
                get: { router.pendingCreate == BuiltInDocTypes.docType.id },
                set: { newValue in
                    if !newValue { router.consumePendingCreate(BuiltInDocTypes.docType.id) }
                }
            )
        )
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
            .frame(minWidth: 760, idealWidth: 1020, minHeight: 600, idealHeight: 740)
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
                                "canAmend": .bool(permission.canAmend),
                                "canCancel": .bool(permission.canCancel)
                            ]
                        )
                    }
                ]
            )
        }
    }

    private func openVisualBuilder(for docType: DocType) {
        #if os(macOS)
        openWindow(id: MercantisShellWindow.visualBuilderID, value: docType.id)
        #else
        selectedDocTypeForBuilder = docType
        #endif
    }

    @ViewBuilder
    private func selectedDocTypeHeader(for document: Document) -> some View {
        if let docType = tooling.navigableDocTypes.first(where: { $0.id == document.id }) {
            let badges = [
                docType.module,
                recordCustomizationBadge(isCustom: docType.isCustom, nonCustomLabel: "Built-in")
            ]

            SelectedRecordHeader(
                title: docType.name,
                badges: badges,
                actions: {
                    AnyView(
                        HStack(spacing: 10) {
                            Button("Open Visual Builder") {
                                openVisualBuilder(for: docType)
                            }
                            .buttonStyle(MercantisSecondaryButtonStyle())

                            Button(role: .destructive) {
                                docTypeToDelete = docType
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .accessibilityLabel("Delete DocType")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!docType.isCustom)
                            .help("Delete DocType")
                        }
                    )
                }
            )
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
