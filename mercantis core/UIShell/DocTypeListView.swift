import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext

    @State private var selectedDocType: DocType?
    @State private var selectedDocTypeForBuilder: DocType?
    @State private var selectedDocTypeID: String?
    @State private var showNewDocTypeSheet = false
    @State private var docTypeToDelete: DocType?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    public init() {}

    public var body: some View {
        List(selection: $selectedDocTypeID) {
            if tooling.docTypes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No DocTypes registered")
                        .font(.headline)
                    Text("Create a new DocType to get started.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            } else {
                ForEach(tooling.docTypes) { docType in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(docType.name)
                                .font(.headline)
                            HStack(spacing: 6) {
                                Text(docType.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(docType.module)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(MercantisTheme.primary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer()

                        HStack(spacing: 8) {
                            Button("Open Visual Builder") {
                                selectedDocTypeForBuilder = docType
                            }
                            .buttonStyle(MercantisSecondaryButtonStyle())

                            if docType.isCustom {
                                Button("Edit") {
                                    selectedDocType = docType
                                }
                                .buttonStyle(MercantisSecondaryButtonStyle())

                                Button("Delete", role: .destructive) {
                                    docTypeToDelete = docType
                                    showDeleteConfirmation = true
                                }
                                .buttonStyle(MercantisDestructiveButtonStyle())
                            } else {
                                Text("Built-in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(docType.id)
                    .listRowBackground(
                        selectedDocTypeID == docType.id
                            ? Color.accentColor.opacity(0.1)
                            : Color.clear
                    )
                }
            }
        }
        .navigationTitle("DocTypes")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Text("\(tooling.docTypes.count) registered")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("New DocType") {
                    showNewDocTypeSheet = true
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                Button("Open Visual Builder") {
                    selectedDocTypeForBuilder = selectedDocTypeForSelection
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
                .disabled(selectedDocTypeForSelection == nil)
            }
        }
        .onAppear {
            tooling.reload()
            if selectedDocTypeID == nil {
                selectedDocTypeID = tooling.docTypes.first?.id
            }
        }
        .onChange(of: tooling.docTypes.map(\.id)) { _, ids in
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
        return tooling.docTypes.first(where: { $0.id == selectedDocTypeID })
    }
}
