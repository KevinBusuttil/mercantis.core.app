//
//  Attachment.swift
//  mercantis core
//
//  Phase C / P3.1 (ADR-043) — File attachments. Metadata for one row in
//  the `attachments` table.
//

import Foundation

/// A file attachment bound to a document (and optionally a specific field).
///
/// Bytes live on disk under the `AttachmentStore` root; this struct carries
/// the metadata persisted in the `attachments` table. Use
/// `AttachmentManager.read(_:)` to materialise the bytes.
public struct Attachment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let documentId: String
    public let docType: String
    /// Bound field key. `nil` for general document attachments not tied to
    /// a specific `FieldType.attachment` field.
    public let fieldKey: String?
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int
    /// Path under the attachment store root. Stable across moves of the
    /// store directory as long as the store is given the new root.
    public let storagePath: String
    public let uploadedAt: Date
    public let uploadedBy: String
    /// Lower-case hex SHA-256 of the file bytes. Used for integrity
    /// verification and (future) content-addressable dedup.
    public let sha256: String

    public init(
        id: String,
        documentId: String,
        docType: String,
        fieldKey: String?,
        fileName: String,
        mimeType: String,
        byteSize: Int,
        storagePath: String,
        uploadedAt: Date,
        uploadedBy: String,
        sha256: String
    ) {
        self.id = id
        self.documentId = documentId
        self.docType = docType
        self.fieldKey = fieldKey
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.storagePath = storagePath
        self.uploadedAt = uploadedAt
        self.uploadedBy = uploadedBy
        self.sha256 = sha256
    }
}

public enum AttachmentError: Error, Sendable, Equatable {
    case notFound(id: String)
    case integrityFailure(id: String)
    case ioFailure(reason: String)
}
