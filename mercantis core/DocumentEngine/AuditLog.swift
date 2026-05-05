//
//  AuditLog.swift
//  mercantis core
//
//  Phase A §3.2 — fills the audit_log table that has existed since migration v1
//  but had no writer. The audit log is distinct from the sync queue (which is
//  pruned per ADR-028); audit rows are append-only and retained.
//

import Foundation
import GRDB

/// One row in the immutable `audit_log` table.
///
/// The audit log records *who did what to which document, when*. It is the
/// canonical source for compliance trails (SOX, financial audit) and is not
/// pruned alongside the sync queue.
public struct AuditLogEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let documentId: String
    public let docType: String
    public let userId: String
    /// `save`, `submit`, `cancel`, `amend`, `delete`, `applyRemote`, …
    public let action: String
    public let timestamp: Date
    /// JSON blob holding before/after field maps and any contextual metadata.
    public let payloadJSON: String

    public init(
        id: String = UUID().uuidString,
        documentId: String,
        docType: String,
        userId: String,
        action: String,
        timestamp: Date = Date(),
        payloadJSON: String = "{}"
    ) {
        self.id = id
        self.documentId = documentId
        self.docType = docType
        self.userId = userId
        self.action = action
        self.timestamp = timestamp
        self.payloadJSON = payloadJSON
    }
}

/// Writes append-only rows into the `audit_log` table. Always invoked inside
/// the same atomic write block as the document mutation it describes, so the
/// audit row and the document update commit together. (§3.2)
public final class AuditLogWriter {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    /// Append an entry inside an existing GRDB write block. Use this from
    /// `DocumentEngine` so audit + mutation share a transaction.
    public func append(_ entry: AuditLogEntry, in db: Database) throws {
        let tsString = ISO8601DateFormatter().string(from: entry.timestamp)
        try db.execute(
            sql: """
                INSERT INTO audit_log
                    (id, documentId, docType, userId, action, timestamp, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                entry.id,
                entry.documentId,
                entry.docType,
                entry.userId,
                entry.action,
                tsString,
                entry.payloadJSON
            ]
        )
    }

    /// Convenience: append a JSON-encoded before/after payload.
    public func append(
        documentId: String,
        docType: String,
        userId: String,
        action: String,
        before: [String: FieldValue]?,
        after: [String: FieldValue]?,
        in db: Database
    ) throws {
        let payloadJSON = try Self.encodePayload(before: before, after: after)
        try append(
            AuditLogEntry(
                documentId: documentId,
                docType: docType,
                userId: userId,
                action: action,
                payloadJSON: payloadJSON
            ),
            in: db
        )
    }

    private static func encodePayload(
        before: [String: FieldValue]?,
        after: [String: FieldValue]?
    ) throws -> String {
        struct Wrapper: Codable {
            let before: [String: FieldValue]?
            let after: [String: FieldValue]?
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Wrapper(before: before, after: after))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Reader API

    /// Return the full audit history for a document, oldest first.
    public func entries(forDocumentId documentId: String) throws -> [AuditLogEntry] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, userId, action, timestamp, payload
                    FROM audit_log
                    WHERE documentId = ?
                    ORDER BY timestamp ASC, id ASC
                    """,
                arguments: [documentId]
            )
            return try rows.map { try Self.entryFromRow($0) }
        }
    }

    /// Return the audit history for a DocType, newest first, paged.
    public func entries(forDocType docType: String, limit: Int = 100, offset: Int = 0) throws -> [AuditLogEntry] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, userId, action, timestamp, payload
                    FROM audit_log
                    WHERE docType = ?
                    ORDER BY timestamp DESC, id DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [docType, limit, max(offset, 0)]
            )
            return try rows.map { try Self.entryFromRow($0) }
        }
    }

    private static func entryFromRow(_ row: Row) throws -> AuditLogEntry {
        let id: String = row["id"] ?? ""
        let documentId: String = row["documentId"] ?? ""
        let docType: String = row["docType"] ?? ""
        let userId: String = row["userId"] ?? ""
        let action: String = row["action"] ?? ""
        let tsString: String = row["timestamp"] ?? ""
        let payload: String = row["payload"] ?? "{}"
        let ts = ISO8601DateFormatter().date(from: tsString) ?? Date(timeIntervalSince1970: 0)
        return AuditLogEntry(
            id: id,
            documentId: documentId,
            docType: docType,
            userId: userId,
            action: action,
            timestamp: ts,
            payloadJSON: payload
        )
    }
}
