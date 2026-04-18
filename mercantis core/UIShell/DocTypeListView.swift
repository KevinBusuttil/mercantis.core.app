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
                        .buttonStyle(MercantisSecondaryButtonStyle())
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
                .buttonStyle(MercantisPrimaryButtonStyle())
                Button("Visual Builder") {
                    showingFormBuilder = true
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
        .sheet(isPresented: $showingNewDocType) {
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
        .sheet(isPresented: $showingFormBuilder) {
            NavigationStack {
                FormBuilderView {
                    tooling.reload()
                }
            }
            .frame(minWidth: 960, idealWidth: 1200, minHeight: 640, idealHeight: 820)
            #if os(macOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
            .environmentObject(tooling)
        }
    }
}
