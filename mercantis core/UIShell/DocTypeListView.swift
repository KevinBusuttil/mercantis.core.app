import SwiftUI

public struct DocTypeListView: View {
    @EnvironmentObject private var tooling: DocTypeToolingContext
    @EnvironmentObject private var router: UIShellRouter

    @State private var selectedDocType: DocType?

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
    }
}
