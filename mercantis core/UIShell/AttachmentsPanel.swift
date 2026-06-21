//
//  AttachmentsPanel.swift
//  mercantis core
//
//  UI for the file-attachment engine (ADR-043). Lists / uploads / deletes
//  the attachments bound to a saved document via `AttachmentManager`.
//
//  Mirrors the Flutter `attachments_panel.dart`. Drop into a record's
//  Attachments tab. On macOS uploads use `NSOpenPanel`; iOS shows a stub
//  note (no document-picker bridge is wired here yet).
//

import SwiftUI
#if canImport(MercantisCore)
import MercantisCore
#endif
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Lists, uploads, and deletes the file attachments bound to a document,
/// backed by `AttachmentManager`.
///
/// The panel only operates on *saved* documents — an empty `documentId`
/// renders a "save first" placeholder, matching the Flutter widget.
public struct AttachmentsPanel: View {

    /// The document these attachments belong to. Empty for an unsaved record.
    private let documentId: String
    private let docType: String
    private let manager: AttachmentManager
    /// Acting user id recorded on the attach / detach audit rows.
    private let userId: String

    @State private var attachments: [Attachment] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var pendingDelete: Attachment?

    public init(
        documentId: String,
        docType: String,
        manager: AttachmentManager,
        userId: String
    ) {
        self.documentId = documentId
        self.docType = docType
        self.manager = manager
        self.userId = userId
    }

    public var body: some View {
        Group {
            if documentId.isEmpty {
                ContentUnavailableView(
                    "Save the document to add attachments",
                    systemImage: "paperclip",
                    description: Text("Attachments can be added once this record has been saved.")
                )
            } else {
                content
            }
        }
        .onAppear(perform: reload)
        .confirmationDialog(
            "Delete this attachment?",
            isPresented: deleteDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { attachment in
            Button("Delete \(attachment.fileName)", role: .destructive) {
                performDelete(attachment)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This permanently removes the file. This action cannot be undone.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MercantisTheme.danger)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MercantisTheme.fillSoft(for: .danger), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if attachments.isEmpty {
                ContentUnavailableView(
                    "No attachments",
                    systemImage: "paperclip",
                    description: Text("Use Add Attachment to upload a file to this record.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(attachments) { attachment in
                        AttachmentRow(
                            attachment: attachment,
                            onDelete: { pendingDelete = attachment }
                        )
                        .disabled(isBusy)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: addAttachment) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Add Attachment", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(MercantisPrimaryButtonStyle())
            .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    // MARK: - Actions

    private func reload() {
        guard !documentId.isEmpty else { return }
        do {
            attachments = try manager.attachments(forDocumentId: documentId)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load attachments: \((error as NSError).localizedDescription)"
        }
    }

    private func addAttachment() {
        guard !documentId.isEmpty else { return }
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBusy = true
        errorMessage = nil
        do {
            let data = try Data(contentsOf: url)
            _ = try manager.attach(
                documentId: documentId,
                docType: docType,
                fileName: url.lastPathComponent,
                mimeType: Self.mimeType(for: url),
                data: data,
                userId: userId
            )
            reload()
        } catch {
            errorMessage = "Upload failed: \((error as NSError).localizedDescription)"
        }
        isBusy = false
        #else
        // iOS: a UIDocumentPickerViewController bridge is not wired here yet.
        // Hosts embedding this panel on iOS should surface their own picker
        // and call `manager.attach(...)` directly.
        errorMessage = "File picking is not available on this platform yet."
        #endif
    }

    private func performDelete(_ attachment: Attachment) {
        isBusy = true
        errorMessage = nil
        do {
            try manager.delete(id: attachment.id, userId: userId)
            reload()
        } catch {
            errorMessage = "Delete failed: \((error as NSError).localizedDescription)"
        }
        pendingDelete = nil
        isBusy = false
    }

    #if os(macOS)
    private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
    #endif
}

/// One attachment row: file glyph, name, size + uploaded date, delete button.
private struct AttachmentRow: View {
    let attachment: Attachment
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 18))
                .foregroundStyle(MercantisTheme.textMuted)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MercantisTheme.textPrimary)
                Text("\(Self.humanSize(attachment.byteSize)) · \(Self.formattedDate(attachment.uploadedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete attachment")
        }
        .padding(.vertical, 4)
    }

    private static func humanSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
