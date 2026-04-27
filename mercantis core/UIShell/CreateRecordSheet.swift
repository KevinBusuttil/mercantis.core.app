import SwiftUI
import MercantisCore

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

    @State private var errorMessage: String?

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

            GenericFormView(docType: docType, document: $draft)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 720, minHeight: 480, idealHeight: 620)
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
