//
//  AttachmentManager.swift
//  mercantis core
//
//  Phase C / P3.1 (ADR-043) — Public attachment API. Wraps the on-disk
//  byte store with the metadata table, integrity checks, and audit-log
//  rows.
//

import Foundation
import GRDB

/// High-level attachment API for Hub and other host apps.
///
/// One `AttachmentManager` owns a `MercantisDatabase` (for metadata) and
/// an `AttachmentStore` (for bytes). `DocumentEngine` optionally holds a
/// reference for cascade-on-delete; standalone callers can construct one
/// directly when they need to attach / read files.
public final class AttachmentManager: @unchecked Sendable {

    private let database: MercantisDatabase
    private let store: AttachmentStore
    private let auditWriter: AuditLogWriter?

    public init(
        database: MercantisDatabase,
        store: AttachmentStore,
        auditWriter: AuditLogWriter? = nil
    ) {
        self.database = database
        self.store = store
        self.auditWriter = auditWriter
    }

    // MARK: - Attach

    /// Persist `data` as an attachment on `(documentId, docType)`,
    /// optionally bound to a `fieldKey`. Writes the bytes, the metadata
    /// row, and an audit-log entry in one atomic write transaction.
    @discardableResult
    public func attach(
        documentId: String,
        docType: String,
        fieldKey: String? = nil,
        fileName: String,
        mimeType: String = "application/octet-stream",
        data: Data,
        userId: String
    ) throws -> Attachment {
        let attachmentId = UUID().uuidString
        let storagePath = try store.write(
            documentId: documentId,
            attachmentId: attachmentId,
            data: data
        )
        let now = Date()
        let attachment = Attachment(
            id: attachmentId,
            documentId: documentId,
            docType: docType,
            fieldKey: fieldKey,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: data.count,
            storagePath: storagePath,
            uploadedAt: now,
            uploadedBy: userId,
            sha256: AttachmentStore.sha256(data)
        )
        do {
            try database.write { db in
                try Self.insert(attachment, in: db)
                if let auditWriter {
                    try auditWriter.append(
                        AuditLogEntry(
                            documentId: documentId,
                            docType: docType,
                            userId: userId,
                            action: "attach",
                            payloadJSON: Self.attachmentSummary(attachment)
                        ),
                        in: db
                    )
                }
            }
        } catch {
            // Roll back the on-disk write if metadata persistence fails.
            try? store.delete(storagePath: storagePath)
            throw error
        }
        return attachment
    }

    // MARK: - Read

    public func read(_ attachment: Attachment) throws -> Data {
        let data = try store.read(storagePath: attachment.storagePath)
        if AttachmentStore.sha256(data) != attachment.sha256 {
            throw AttachmentError.integrityFailure(id: attachment.id)
        }
        return data
    }

    public func read(id: String) throws -> Data {
        guard let attachment = try metadata(id: id) else {
            throw AttachmentError.notFound(id: id)
        }
        return try read(attachment)
    }

    // MARK: - Listing

    public func attachments(forDocumentId documentId: String) throws -> [Attachment] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, fieldKey, fileName, mimeType,
                           byteSize, storagePath, uploadedAt, uploadedBy, sha256
                    FROM attachments
                    WHERE documentId = ?
                    ORDER BY uploadedAt ASC, id ASC
                    """,
                arguments: [documentId]
            )
            return try rows.map { try Self.attachmentFromRow($0) }
        }
    }

    public func attachments(forField fieldKey: String, on documentId: String) throws -> [Attachment] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, fieldKey, fileName, mimeType,
                           byteSize, storagePath, uploadedAt, uploadedBy, sha256
                    FROM attachments
                    WHERE documentId = ? AND fieldKey = ?
                    ORDER BY uploadedAt ASC, id ASC
                    """,
                arguments: [documentId, fieldKey]
            )
            return try rows.map { try Self.attachmentFromRow($0) }
        }
    }

    public func metadata(id: String) throws -> Attachment? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, documentId, docType, fieldKey, fileName, mimeType,
                           byteSize, storagePath, uploadedAt, uploadedBy, sha256
                    FROM attachments
                    WHERE id = ?
                    """,
                arguments: [id]
            ) else { return nil }
            return try Self.attachmentFromRow(row)
        }
    }

    // MARK: - Delete

    /// Remove a single attachment by id. Best-effort: tolerates a missing
    /// on-disk file (the metadata row is the source of truth).
    public func delete(id: String, userId: String) throws {
        guard let existing = try metadata(id: id) else {
            throw AttachmentError.notFound(id: id)
        }
        try database.write { db in
            try db.execute(sql: "DELETE FROM attachments WHERE id = ?", arguments: [id])
            if let auditWriter {
                try auditWriter.append(
                    AuditLogEntry(
                        documentId: existing.documentId,
                        docType: existing.docType,
                        userId: userId,
                        action: "detach",
                        payloadJSON: Self.attachmentSummary(existing)
                    ),
                    in: db
                )
            }
        }
        try? store.delete(storagePath: existing.storagePath)
    }

    /// Cascade: remove every attachment for `documentId`. Called by
    /// `DocumentEngine.delete(...)` when an `AttachmentManager` is wired
    /// into the engine.
    public func deleteAll(forDocumentId documentId: String, userId: String) throws {
        let existing = try attachments(forDocumentId: documentId)
        guard !existing.isEmpty else { return }

        try database.write { db in
            try db.execute(
                sql: "DELETE FROM attachments WHERE documentId = ?",
                arguments: [documentId]
            )
            if let auditWriter {
                try auditWriter.append(
                    AuditLogEntry(
                        documentId: documentId,
                        docType: existing.first?.docType ?? "",
                        userId: userId,
                        action: "detachAll",
                        payloadJSON: "{\"count\":\(existing.count)}"
                    ),
                    in: db
                )
            }
        }
        try? store.deleteAll(documentId: documentId)
    }

    // MARK: - Internals

    private static func insert(_ attachment: Attachment, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO attachments
                    (id, documentId, docType, fieldKey, fileName, mimeType,
                     byteSize, storagePath, uploadedAt, uploadedBy, sha256)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                attachment.id,
                attachment.documentId,
                attachment.docType,
                attachment.fieldKey,
                attachment.fileName,
                attachment.mimeType,
                attachment.byteSize,
                attachment.storagePath,
                ISO8601DateFormatter().string(from: attachment.uploadedAt),
                attachment.uploadedBy,
                attachment.sha256,
            ]
        )
    }

    private static func attachmentFromRow(_ row: Row) throws -> Attachment {
        let id: String = row["id"] ?? ""
        let documentId: String = row["documentId"] ?? ""
        let docType: String = row["docType"] ?? ""
        let fieldKey: String? = row["fieldKey"]
        let fileName: String = row["fileName"] ?? ""
        let mimeType: String = row["mimeType"] ?? "application/octet-stream"
        let byteSize: Int = row["byteSize"] ?? 0
        let storagePath: String = row["storagePath"] ?? ""
        let uploadedAtStr: String = row["uploadedAt"] ?? ""
        let uploadedBy: String = row["uploadedBy"] ?? ""
        let sha256: String = row["sha256"] ?? ""
        let uploadedAt = ISO8601DateFormatter().date(from: uploadedAtStr) ?? Date(timeIntervalSince1970: 0)
        return Attachment(
            id: id,
            documentId: documentId,
            docType: docType,
            fieldKey: fieldKey,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: byteSize,
            storagePath: storagePath,
            uploadedAt: uploadedAt,
            uploadedBy: uploadedBy,
            sha256: sha256
        )
    }

    private static func attachmentSummary(_ a: Attachment) -> String {
        // Shortened JSON suitable for an audit_log payload — full row is
        // already in `attachments`, so we just record the identifying bits.
        let escapedName = a.fileName.replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"attachmentId\":\"\(a.id)\",\"fileName\":\"\(escapedName)\",\"byteSize\":\(a.byteSize),\"sha256\":\"\(a.sha256)\"}"
    }
}
