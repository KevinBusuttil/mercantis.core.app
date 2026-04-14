//
//  DocumentEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

/// Handles all CRUD operations on documents.
/// Every persistent write atomically appends a MutationRecord to the sync queue. (ADR-002, ADR-005)
///
/// Direct SQLite writes that bypass the DocumentEngine are prohibited. (ADR-005)
public final class DocumentEngine {

    private let database: MercantisDatabase
    private let registry: MetadataRegistry
    private let validator: SchemaValidator
    private let eventBus: EventBus
    private let deviceId: String
    private let userId: String

    public init(
        database: MercantisDatabase,
        registry: MetadataRegistry,
        eventBus: EventBus,
        deviceId: String,
        userId: String
    ) {
        self.database = database
        self.registry = registry
        self.validator = SchemaValidator()
        self.eventBus = eventBus
        self.deviceId = deviceId
        self.userId = userId
    }

    // MARK: - Save

    /// Create or update a document. Appends an `upsertDocument` mutation atomically.
    public func save(_ document: Document) throws {
        // Validate the document's DocType if it is registered.
        if let docType = registry.get(document.docType) {
            try validator.validate(docType)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Encode field values as the payload JSON.
        let payloadData = try encoder.encode(document.fields)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        // Build the mutation record.
        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(UpsertPayload(document: document)),
            deviceId: deviceId,
            userId: userId,
            localTimestamp: Date(),
            syncVersion: document.syncVersion,
            status: .pending
        )
        let mutationPayloadString = String(data: mutation.payload, encoding: .utf8) ?? "{}"
        let mutationTimestamp = ISO8601DateFormatter().string(from: mutation.localTimestamp)
        let createdAtString = ISO8601DateFormatter().string(from: document.createdAt)
        let updatedAtString = ISO8601DateFormatter().string(from: document.updatedAt)

        try database.write { db in
            // Upsert the document row.
            try db.execute(
                sql: """
                    INSERT INTO documents
                        (id, doctype, company, status, createdAt, updatedAt, syncVersion, syncState, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        company     = excluded.company,
                        status      = excluded.status,
                        updatedAt   = excluded.updatedAt,
                        syncVersion = excluded.syncVersion,
                        syncState   = excluded.syncState,
                        payload     = excluded.payload
                    """,
                arguments: [
                    document.id,
                    document.docType,
                    document.company,
                    document.status,
                    createdAtString,
                    updatedAtString,
                    document.syncVersion,
                    document.syncState.rawValue,
                    payloadString
                ]
            )

            // Upsert child rows.
            for (tableName, rows) in document.children {
                for row in rows {
                    let rowPayload = (try? encoder.encode(row.fields))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    try db.execute(
                        sql: """
                            INSERT INTO document_children
                                (id, parentId, parentDocType, tableName, rowIndex, payload)
                            VALUES (?, ?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                rowIndex = excluded.rowIndex,
                                payload  = excluded.payload
                            """,
                        arguments: [
                            row.id,
                            document.id,
                            document.docType,
                            tableName,
                            row.rowIndex,
                            rowPayload
                        ]
                    )
                }
            }

            // Atomically append the mutation record to the sync queue.
            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutation.id.uuidString,
                    mutation.type.rawValue,
                    mutationPayloadString,
                    mutation.deviceId,
                    mutation.userId,
                    mutationTimestamp,
                    mutation.syncVersion,
                    mutation.status.rawValue
                ]
            )
        }

        eventBus.publish(EventBus.Event(
            name: "document.saved",
            docType: document.docType,
            documentId: document.id,
            payload: [:]
        ))
    }

    // MARK: - Delete

    /// Delete a document. Appends a `deleteDocument` mutation atomically.
    public func delete(docType: String, id: String) throws {
        let mutation = MutationRecord(
            id: UUID(),
            type: .deleteDocument,
            payload: Data("{\"id\":\"\(id)\",\"docType\":\"\(docType)\"}".utf8),
            deviceId: deviceId,
            userId: userId,
            localTimestamp: Date(),
            syncVersion: 0,
            status: .pending
        )
        let mutationPayloadString = String(data: mutation.payload, encoding: .utf8) ?? "{}"
        let mutationTimestamp = ISO8601DateFormatter().string(from: mutation.localTimestamp)

        try database.write { db in
            // Cascade delete children (enforced by FK constraint, but explicit here for clarity).
            try db.execute(sql: "DELETE FROM document_children WHERE parentId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM documents WHERE id = ? AND doctype = ?", arguments: [id, docType])

            try db.execute(
                sql: """
                    INSERT INTO sync_queue
                        (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    mutation.id.uuidString,
                    mutation.type.rawValue,
                    mutationPayloadString,
                    mutation.deviceId,
                    mutation.userId,
                    mutationTimestamp,
                    mutation.syncVersion,
                    mutation.status.rawValue
                ]
            )
        }

        eventBus.publish(EventBus.Event(
            name: "document.deleted",
            docType: docType,
            documentId: id,
            payload: [:]
        ))
    }

    // MARK: - Fetch

    /// Fetch a single document by type and ID.
    public func fetch(docType: String, id: String) throws -> Document? {
        let row = try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, doctype, company, status, createdAt, updatedAt,
                           syncVersion, syncState, payload
                    FROM documents
                    WHERE id = ? AND doctype = ?
                    LIMIT 1
                    """,
                arguments: [id, docType]
            )
        }
        guard let row = row else { return nil }
        return try documentFromRow(row)
    }

    // MARK: - List

    /// Fetch all documents of a given type, with optional field filters.
    public func list(docType: String, filters: [String: FieldValue]? = nil) throws -> [Document] {
        let rows = try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, doctype, company, status, createdAt, updatedAt,
                           syncVersion, syncState, payload
                    FROM documents
                    WHERE doctype = ?
                    ORDER BY updatedAt DESC
                    """,
                arguments: [docType]
            )
        }

        var documents = try rows.map { try documentFromRow($0) }

        // Apply in-memory filters on field values.
        if let filters = filters {
            documents = documents.filter { doc in
                filters.allSatisfy { (key, value) in
                    doc.fields[key] == value
                }
            }
        }

        return documents
    }

    // MARK: - Private Helpers

    private func documentFromRow(_ row: Row) throws -> Document {
        guard let id: String = row["id"], !id.isEmpty else {
            throw DocumentEngineError.malformedRow
        }

        let docType: String = row["doctype"] ?? ""
        let company: String = row["company"] ?? ""
        let status: String = row["status"] ?? ""
        let createdAt = parseDate(row["createdAt"] as String?) ?? Date()
        let updatedAt = parseDate(row["updatedAt"] as String?) ?? Date()
        let syncVersion: Int64 = row["syncVersion"] ?? 0
        let syncStateRaw: String = row["syncState"] ?? "local"
        let syncState = SyncState(rawValue: syncStateRaw) ?? .local
        let payloadString: String = row["payload"] ?? "{}"

        var fields: [String: FieldValue] = [:]
        if let payloadData = payloadString.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            fields = (try? decoder.decode([String: FieldValue].self, from: payloadData)) ?? [:]
        }

        return Document(
            id: id,
            docType: docType,
            company: company,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncVersion: syncVersion,
            syncState: syncState,
            fields: fields,
            children: [:]
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Errors

    public enum DocumentEngineError: Error, Sendable {
        case malformedRow
        case docTypeNotFound(String)
    }

    // MARK: - Private Types

    private struct UpsertPayload: Encodable {
        let id: String
        let docType: String
        let company: String
        let status: String

        init(document: Document) {
            self.id = document.id
            self.docType = document.docType
            self.company = document.company
            self.status = document.status
        }
    }
}
