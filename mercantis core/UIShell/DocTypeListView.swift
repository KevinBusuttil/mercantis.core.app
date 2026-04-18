import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext

    @State private var selectedDocType: DocType?
    @State private var showingNewDocType = false
    @State private var showingFormBuilder = false

    public init() {}

    public var body: some View {
        List {
            ForEach(tooling.docTypes) { docType in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(docType.name)
                            .font(.headline)
                        Text(docType.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if docType.isCustom {
                        Button("Edit") {
                            selectedDocType = docType
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
        .navigationTitle("DocTypes")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("New DocType") {
                    showingNewDocType = true
                }
                Button("Visual Builder") {
                    showingFormBuilder = true
                }
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
            .environmentObject(tooling)
        }
        .sheet(isPresented: $showingNewDocType) {
            NavigationStack {
                DocTypeBuilderView {
                    tooling.reload()
                }
            }
            .environmentObject(tooling)
        }
        .sheet(isPresented: $showingFormBuilder) {
            NavigationStack {
                FormBuilderView {
                    tooling.reload()
                }
            }
            .environmentObject(tooling)
        }
    }
}
