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
    ///
    /// If the document belongs to a submittable DocType and has `docStatus == 1` (Submitted),
    /// only fields marked `allowOnSubmit: true` can be changed. (ADR-013)
    public func save(_ document: Document) throws {
        // Validate the document's DocType if it is registered.
        if let docType = registry.get(document.docType) {
            try validator.validate(docType)

            // ADR-013: Immutability enforcement for submitted documents.
            if document.docStatus == 1 && docType.isSubmittable {
                try enforceSubmitImmutability(document: document, docType: docType)
            }
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
                        (id, doctype, company, status, createdAt, updatedAt, syncVersion, syncState, docStatus, amendedFrom, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        company     = excluded.company,
                        status      = excluded.status,
                        updatedAt   = excluded.updatedAt,
                        syncVersion = excluded.syncVersion,
                        syncState   = excluded.syncState,
                        docStatus   = excluded.docStatus,
                        amendedFrom = excluded.amendedFrom,
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
                    document.docStatus,
                    document.amendedFrom,
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
        // ADR-013: Submitted documents cannot be deleted directly.
        if let existing = try fetch(docType: docType, id: id), existing.docStatus == 1 {
            throw DocumentEngineError.cannotDeleteSubmitted(id: id)
        }

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

    // MARK: - Submit (ADR-013)

    /// Submit a document, transitioning it from Draft (docStatus 0) to Submitted (docStatus 1).
    ///
    /// - The DocType must have `isSubmittable: true`.
    /// - The document must currently be in Draft state (`docStatus == 0`).
    /// - After submission, the document becomes immutable except for `allowOnSubmit` fields.
    public func submit(_ document: inout Document) throws {
        guard let docType = registry.get(document.docType) else {
            throw DocumentEngineError.docTypeNotFound(document.docType)
        }
        guard docType.isSubmittable else {
            throw DocumentEngineError.notSubmittable(docType: document.docType)
        }
        guard document.docStatus == 0 else {
            throw DocumentEngineError.invalidDocStatusTransition(
                from: document.docStatus, to: 1, id: document.id
            )
        }

        document.docStatus = 1
        document.updatedAt = Date()
        try save(document)

        eventBus.publish(EventBus.Event(
            name: "document.submitted",
            docType: document.docType,
            documentId: document.id,
            payload: [:]
        ))
    }

    // MARK: - Cancel (ADR-013)

    /// Cancel a submitted document, transitioning it from Submitted (docStatus 1) to
    /// Cancelled (docStatus 2).
    ///
    /// Before cancelling, checks for linked submitted documents that reference this one.
    /// If any downstream submitted document holds a Link field pointing to this document,
    /// the cancel is rejected. (ADR-013)
    public func cancel(_ document: inout Document) throws {
        guard let docType = registry.get(document.docType) else {
            throw DocumentEngineError.docTypeNotFound(document.docType)
        }
        guard docType.isSubmittable else {
            throw DocumentEngineError.notSubmittable(docType: document.docType)
        }
        guard document.docStatus == 1 else {
            throw DocumentEngineError.invalidDocStatusTransition(
                from: document.docStatus, to: 2, id: document.id
            )
        }

        // Check for linked submitted documents that reference this one.
        let blockingDocuments = try findLinkedSubmittedDocuments(documentId: document.id)
        if !blockingDocuments.isEmpty {
            throw DocumentEngineError.cancelBlockedByLinks(
                id: document.id,
                blockingIds: blockingDocuments
            )
        }

        document.docStatus = 2
        document.updatedAt = Date()
        try save(document)

        eventBus.publish(EventBus.Event(
            name: "document.cancelled",
            docType: document.docType,
            documentId: document.id,
            payload: [:]
        ))
    }

    // MARK: - Amend (ADR-013)

    /// Amend a cancelled document by creating a new Draft copy. (ADR-013)
    ///
    /// - All fields are copied from the cancelled document.
    /// - `docStatus` is reset to 0 (Draft).
    /// - `amendedFrom` is set to the cancelled document's ID.
    /// - A new document ID is generated.
    ///
    /// Returns the new amended document. The caller must save it via `save()`.
    public func amend(_ document: Document) throws -> Document {
        guard let docType = registry.get(document.docType) else {
            throw DocumentEngineError.docTypeNotFound(document.docType)
        }
        guard docType.isSubmittable else {
            throw DocumentEngineError.notSubmittable(docType: document.docType)
        }
        guard document.docStatus == 2 else {
            throw DocumentEngineError.invalidDocStatusTransition(
                from: document.docStatus, to: 0, id: document.id
            )
        }

        let newId = UUID().uuidString
        let now = Date()

        var amended = Document(
            id: newId,
            docType: document.docType,
            company: document.company,
            status: document.status,
            createdAt: now,
            updatedAt: now,
            syncVersion: 0,
            syncState: .local,
            docStatus: 0,
            amendedFrom: document.id,
            fields: document.fields,
            children: document.children
        )

        // Reset child row IDs to new UUIDs so they don't conflict.
        var newChildren: [String: [ChildRow]] = [:]
        for (tableName, rows) in amended.children {
            newChildren[tableName] = rows.map { row in
                ChildRow(id: UUID().uuidString, rowIndex: row.rowIndex, fields: row.fields)
            }
        }
        amended.children = newChildren

        try save(amended)

        eventBus.publish(EventBus.Event(
            name: "document.amended",
            docType: document.docType,
            documentId: newId,
            payload: ["amendedFrom": document.id]
        ))

        return amended
    }

    // MARK: - Fetch

    /// Fetch a single document by type and ID.
    public func fetch(docType: String, id: String) throws -> Document? {
        let row = try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, doctype, company, status, createdAt, updatedAt,
                           syncVersion, syncState, docStatus, amendedFrom, payload
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
                           syncVersion, syncState, docStatus, amendedFrom, payload
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

    /// ADR-013: Check that only `allowOnSubmit` fields have been modified on a submitted document.
    private func enforceSubmitImmutability(document: Document, docType: DocType) throws {
        guard let existing = try fetch(docType: document.docType, id: document.id) else {
            // New document — no immutability check needed.
            return
        }
        guard existing.docStatus == 1 else { return }

        let allowedKeys = Set(docType.fields.filter { $0.allowOnSubmit }.map { $0.key })

        for (key, newValue) in document.fields {
            let oldValue = existing.fields[key]
            if oldValue != newValue && !allowedKeys.contains(key) {
                throw DocumentEngineError.fieldImmutableAfterSubmit(
                    fieldKey: key, documentId: document.id
                )
            }
        }
    }

    /// ADR-013: Find submitted documents that link to the given document ID.
    ///
    /// Checks all registered DocTypes for Link fields, then queries only those DocTypes
    /// for submitted documents whose payload contains the target ID. This is more targeted
    /// than a full table scan but still uses a JSON payload search; a dedicated link reference
    /// table would be more efficient for large datasets.
    private func findLinkedSubmittedDocuments(documentId: String) throws -> [String] {
        // Gather DocType IDs that have Link fields (potential linkers).
        let allDocTypes = registry.all()
        let linkingDocTypeIds = allDocTypes
            .filter { dt in dt.fields.contains(where: { $0.type == .link }) }
            .map { $0.id }

        guard !linkingDocTypeIds.isEmpty else { return [] }

        // Query each linking DocType for submitted documents whose payload references documentId.
        var blockingIds: [String] = []
        for docTypeId in linkingDocTypeIds {
            let rows = try database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM documents
                        WHERE docStatus = 1
                          AND doctype = ?
                          AND payload LIKE ?
                          AND id != ?
                        """,
                    arguments: [docTypeId, "%\(documentId)%", documentId]
                )
            }
            blockingIds.append(contentsOf: rows.compactMap { $0["id"] as String? })
        }
        return blockingIds
    }

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
        let docStatus: Int = row["docStatus"] ?? 0
        let amendedFrom: String? = row["amendedFrom"]
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
            docStatus: docStatus,
            amendedFrom: amendedFrom,
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
        case notSubmittable(docType: String)
        case invalidDocStatusTransition(from: Int, to: Int, id: String)
        case fieldImmutableAfterSubmit(fieldKey: String, documentId: String)
        case cancelBlockedByLinks(id: String, blockingIds: [String])
        case cannotDeleteSubmitted(id: String)
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
