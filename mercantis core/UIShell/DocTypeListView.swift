import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    @EnvironmentObject private var router: UIShellRouter

    @State private var selectedDocType: DocType?
    @State private var docTypeToDelete: DocType?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    public init() {}

    public var body: some View {
        List {
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

                        if docType.isCustom {
                            HStack(spacing: 8) {
                                Button("Edit") {
                                    selectedDocType = docType
                                }
                                .buttonStyle(MercantisSecondaryButtonStyle())

                                Button("Delete", role: .destructive) {
                                    docTypeToDelete = docType
                                    showDeleteConfirmation = true
                                }
                                .buttonStyle(MercantisDestructiveButtonStyle())
                            }
                        } else {
                            Text("Built-in")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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
                    router.openNewDocType()
                }
                .buttonStyle(MercantisPrimaryButtonStyle())
                Button("Visual Builder") {
                    router.openVisualBuilder()
                }
                .buttonStyle(MercantisSecondaryButtonStyle())
            }
        }
        .onAppear {
            tooling.reload()
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
}
