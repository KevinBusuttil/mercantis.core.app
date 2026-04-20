import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var selectedDocType: DocType?
    @State private var selectedDocTypeForBuilder: DocType?
    @State private var selectedDocTypeID: String?
    @State private var showNewDocTypeSheet = false
    @State private var docTypeToDelete: DocType?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    public init() {}

    public var body: some View {
        RecordCollectionHostView(
            preferenceKey: "docType.management",
            docType: BuiltInDocTypes.docType,
            documents: docTypeDocuments,
            configuration: RecordCollectionViewConfiguration(
                supportedViewModes: [.list, .browse, .detail],
                defaultViewMode: .list
            ),
            allowsDetailEditing: false,
            initialSelectedDocumentID: selectedDocTypeID,
            onSelectionChange: { selected in
                selectedDocTypeID = selected?.id
            }
        )
        .navigationTitle("DocTypes")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Text("\(tooling.navigableDocTypes.count) registered")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("New DocType") {
                    showNewDocTypeSheet = true
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                Button("Edit DocType") {
                    guard let selectedDocTypeForSelection else { return }
                    selectedDocType = selectedDocTypeForSelection
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
                .disabled(selectedDocTypeForSelection?.isCustom != true)
                Button("Open Visual Builder") {
                    guard let selectedDocTypeForSelection else { return }
                    openVisualBuilder(for: selectedDocTypeForSelection)
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                .disabled(selectedDocTypeForSelection == nil)
                Button("Delete DocType", role: .destructive) {
                    guard let selectedDocTypeForSelection else { return }
                    docTypeToDelete = selectedDocTypeForSelection
                    showDeleteConfirmation = true
                }
                .buttonStyle(MercantisDestructiveButtonStyle())
                .disabled(selectedDocTypeForSelection?.isCustom != true)
            }
        }
        .onAppear {
            tooling.reload()
            if selectedDocTypeID == nil {
                selectedDocTypeID = tooling.navigableDocTypes.first?.id
            }
        }
        .onChange(of: tooling.navigableDocTypes.map(\.id)) { _, ids in
            if let selectedDocTypeID, ids.contains(selectedDocTypeID) {
                return
            }
            self.selectedDocTypeID = ids.first
        }
        .sheet(item: $selectedDocType) { docType in
            NavigationStack {
                DocTypeBuilderView(docType: docType) {
                    tooling.reload()
                }
            }
            .frame(minWidth: 640, idealWidth: 820, minHeight: 520, idealHeight: 680)
            #if os(macOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            .environmentObject(tooling)
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

    private var selectedDocTypeForSelection: DocType? {
        guard let selectedDocTypeID else { return nil }
        return tooling.navigableDocTypes.first(where: { $0.id == selectedDocTypeID })
    }

    private var docTypeDocuments: [Document] {
        tooling.navigableDocTypes.map { docType in
            Document(
                id: docType.id,
                docType: BuiltInDocTypes.docType.id,
                company: "",
                status: docType.isCustom ? "Custom" : "Built-in",
                createdAt: Date.distantPast,
                updatedAt: Date(),
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
}
