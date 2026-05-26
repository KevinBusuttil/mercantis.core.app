import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif

/// Modal sheet used to create a new record of a given `DocType`.
///
/// Rendered from every entry point that can initiate "New" — workspace toolbar,
/// Quick Create, Command Bar — so users see the same dialog regardless of origin.
/// For DocType-level metadata authoring, `DocTypeListView` presents its own
/// `DocTypeBuilderView` sheet; this primitive is the generic fallback.
struct CreateRecordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let docType: DocType
    @Binding var draft: Document
    let onCreate: (Document) throws -> Void
    let linkSearchProvider: ((String, String) -> [Document])?
    let childDocTypeProvider: ((String) -> DocType?)?

    @State private var errorMessage: String?

    init(
        docType: DocType,
        draft: Binding<Document>,
        onCreate: @escaping (Document) throws -> Void,
        linkSearchProvider: ((String, String) -> [Document])? = nil,
        childDocTypeProvider: ((String) -> DocType?)? = nil
    ) {
        self.docType = docType
        self._draft = draft
        self.onCreate = onCreate
        self.linkSearchProvider = linkSearchProvider
        self.childDocTypeProvider = childDocTypeProvider
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MercantisTheme.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MercantisTheme.fillSoft(for: .danger))
            }

            GenericFormView(
                docType: docType,
                document: $draft,
                linkSearchProvider: linkSearchProvider,
                childDocTypeProvider: childDocTypeProvider
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        // Wider ideal width so child-table fields have room to breathe (UX-3
        // Option C) — most transactional records (Sales Order, Purchase Order,
        // Stock Entry) embed line-item grids with 6–8 columns.
        .frame(minWidth: 640, idealWidth: 960, minHeight: 520, idealHeight: 680)
        #if os(macOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New \(docType.name)")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text(docType.module)
                    .font(.caption)
                    .foregroundStyle(MercantisTheme.textMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(MercantisTheme.surface)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(MercantisSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("Create", action: performCreate)
                .buttonStyle(MercantisPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(MercantisTheme.surface)
    }

    private func performCreate() {
        errorMessage = nil
        do {
            try onCreate(draft)
            dismiss()
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }
}
