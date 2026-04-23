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
    private let eventEmitter: EventEmitter
    private let validationPipeline: ValidationPipeline
    private let deviceId: String
    private let userId: String

    public init(
        database: MercantisDatabase,
        registry: MetadataRegistry,
        deviceId: String,
        userId: String,
        eventEmitter: EventEmitter = EventEmitter(),
        validationPipeline: ValidationPipeline = ValidationPipeline()
    ) {
        self.database = database
        self.registry = registry
        self.validator = SchemaValidator()
        self.eventEmitter = eventEmitter
        self.validationPipeline = validationPipeline
        self.deviceId = deviceId
        self.userId = userId
    }

    // MARK: - Save

    /// Create or update a document. Appends an `upsertDocument` mutation atomically.
    ///
    /// If the document belongs to a submittable DocType and has `docStatus == 1` (Submitted),
    /// only fields marked `allowOnSubmit: true` can be changed. (ADR-013)
    public func save(_ document: Document) throws {
        // ADR-023: Optimistic concurrency check via updatedAt.
        // ADR-024: Load existing fields for diff computation.
        // P1.5: isNew drives `DocumentOperation.create` vs `.write` in the pipeline.
        let existing = try loadExistingState(docType: document.docType, id: document.id)

        if let docType = registry.get(document.docType) {
            try validator.validate(docType)
            try runValidationPipeline(on: document, docType: docType, isNew: existing == nil)

            // ADR-013: Immutability enforcement for submitted documents.
            if document.docStatus == 1 && docType.isSubmittable {
                try enforceSubmitImmutability(document: document, docType: docType)
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let payloadData = try encoder.encode(document.fields)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        if let stored = existing?.updatedAt {
            let inMemoryTimestamp = ISO8601DateFormatter().string(from: document.updatedAt)
            if stored != inMemoryTimestamp {
                throw DocumentEngineError.concurrencyConflict(documentId: document.id)
            }
        }
        let oldFields = existing?.fields ?? [:]

        let mutation = MutationRecord(
            id: UUID(),
            type: .upsertDocument,
            payload: try encoder.encode(document),
            deviceId: deviceId,
            userId: userId,
            localTimestamp: Date(),
            syncVersion: document.syncVersion,
            status: .pending
        )
        let createdAtString = ISO8601DateFormatter().string(from: document.createdAt)
        let saveTimestamp = Date()
        let updatedAtString = ISO8601DateFormatter().string(from: saveTimestamp)

        try database.write { db in
            try upsertDocumentRow(
                db, document: document,
                createdAt: createdAtString,
                updatedAt: updatedAtString,
                syncState: document.syncState,
                payloadString: payloadString
            )
            try syncChildRows(db, document: document, encoder: encoder)
            try appendMutation(db, mutation: mutation)
            try recordDocumentVersion(
                db, document: document,
                savedAt: saveTimestamp,
                savedBy: userId,
                oldFields: oldFields
            )
        }

        eventEmitter.publish(DocumentSavedEvent(
            document: document,
            docType: document.docType
        ))
    }

    // MARK: - Apply Remote (ADR-005, P0.2)

    /// Apply a remote upsert received via the sync engine. (ADR-005)
    ///
    /// Unlike `save(_:)`:
    /// - **No new `MutationRecord` is appended** to `sync_queue` — the remote
    ///   mutation is the record; the `SyncEngine` marks it applied separately.
    /// - **No optimistic-concurrency check** — conflict detection is the
    ///   `SyncEngine`'s responsibility via `ConflictResolver` (ADR-006).
    /// - `syncState` is forced to `.synced` and `syncVersion` is taken from
    ///   the remote mutation.
    ///
    /// The `ValidationPipeline` (ADR-022), submit-immutability guard (ADR-013),
    /// and `DocumentVersion` diff recording (ADR-024) all fire as they do for
    /// local saves. A `DocumentSavedEvent` is emitted on completion so UI
    /// observers refresh.
    public func applyRemote(_ document: Document, from mutation: MutationRecord) throws {
        var doc = document
        doc.syncVersion = mutation.syncVersion
        doc.syncState = .synced

        let existing = try loadExistingState(docType: doc.docType, id: doc.id)

        if let docType = registry.get(doc.docType) {
            try validator.validate(docType)
            try runValidationPipeline(on: doc, docType: docType, isNew: existing == nil)
            if doc.docStatus == 1 && docType.isSubmittable {
                try enforceSubmitImmutability(document: doc, docType: docType)
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(doc.fields)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"

        let oldFields = existing?.fields ?? [:]

        let createdAtString = ISO8601DateFormatter().string(from: doc.createdAt)
        let updatedAtString = ISO8601DateFormatter().string(from: doc.updatedAt)
        let savedAt = Date()
        let savedBy = mutation.userId.isEmpty ? userId : mutation.userId

        try database.write { db in
            try upsertDocumentRow(
                db, document: doc,
                createdAt: createdAtString,
                updatedAt: updatedAtString,
                syncState: .synced,
                payloadString: payloadString
            )
            try syncChildRows(db, document: doc, encoder: encoder)
            try recordDocumentVersion(
                db, document: doc,
                savedAt: savedAt,
                savedBy: savedBy,
                oldFields: oldFields
            )
        }

        eventEmitter.publish(DocumentSavedEvent(
            document: doc,
            docType: doc.docType
        ))
    }

    // MARK: - Delete

    /// Delete a document. Appends a `deleteDocument` mutation atomically.
    public func delete(docType: String, id: String) throws {
        // ADR-013: Submitted documents cannot be deleted directly.
        if let existing = try fetch(docType: docType, id: id), existing.docStatus == 1 {
            throw DocumentEngineError.cannotDeleteSubmitted(id: id)
        }

        let deletePayload = try JSONEncoder().encode(["id": id, "docType": docType])
        let mutation = MutationRecord(
            id: UUID(),
            type: .deleteDocument,
            payload: deletePayload,
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

        eventEmitter.publish(DocumentDeletedEvent(
            documentId: id,
            docType: docType
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

        eventEmitter.publish(DocumentSubmittedEvent(
            document: document,
            docType: document.docType
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

        eventEmitter.publish(DocumentCancelledEvent(
            document: document,
            docType: document.docType
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

        eventEmitter.publish(DocumentAmendedEvent(
            newDocumentId: newId,
            amendedFrom: document.id,
            docType: document.docType
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
        var doc = try documentFromRow(row)
        doc.children = try fetchChildren(parentId: doc.id)
        return doc
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

        // Load child rows for each document.
        for i in documents.indices {
            documents[i].children = try fetchChildren(parentId: documents[i].id)
        }

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

    // MARK: - Versions (ADR-024, P0.8)

    /// Return the full append-only version history for a document, oldest first.
    ///
    /// Each `DocumentVersion` captures the field-level diff that was applied by a single
    /// `DocumentEngine.save` (or `applyRemote`). Saves that produce no field changes do not
    /// write a version row, so consecutive timestamps need not imply a visible change.
    public func versions(of documentId: String) throws -> [DocumentVersion] {
        let rows = try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, documentId, docType, savedAt, savedBy, fieldDiffs
                    FROM document_versions
                    WHERE documentId = ?
                    ORDER BY savedAt ASC
                    """,
                arguments: [documentId]
            )
        }
        return try rows.map { try documentVersionFromRow($0) }
    }

    /// Return the document version that was in effect at `timestamp` — i.e. the most
    /// recent version whose `savedAt` is less than or equal to `timestamp`. Returns `nil`
    /// if no version was recorded at or before that instant.
    public func version(of documentId: String, at timestamp: Date) throws -> DocumentVersion? {
        let cutoff = ISO8601DateFormatter().string(from: timestamp)
        let row = try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, documentId, docType, savedAt, savedBy, fieldDiffs
                    FROM document_versions
                    WHERE documentId = ? AND savedAt <= ?
                    ORDER BY savedAt DESC
                    LIMIT 1
                    """,
                arguments: [documentId, cutoff]
            )
        }
        guard let row = row else { return nil }
        return try documentVersionFromRow(row)
    }

    // MARK: - Private Helpers

    /// Run the full ValidationPipeline for a document under its DocType. (ADR-022)
    ///
    /// `isNew` selects the `DocumentOperation` used by `PermissionStage`:
    /// `.create` when the document has never been persisted, `.write` otherwise.
    /// Callers that explicitly change `docStatus` (submit / cancel / amend) are
    /// still enforced by the ADR-013 guards; `.write` is used for the save path
    /// that piggybacks on those transitions.
    private func runValidationPipeline(
        on document: Document,
        docType: DocType,
        isNew: Bool
    ) throws {
        let ctx = ValidationContext(
            docType: docType,
            userId: userId,
            operation: isNew ? .create : .write,
            expressionEvaluator: ExpressionEvaluator(),
            documentExists: { [weak self] linkedDocType, linkedId in
                guard let self else { return true }
                return (try? self.fetch(docType: linkedDocType, id: linkedId)) != nil
            },
            uniqueConflictExists: { [weak self] docTypeName, fieldKey, value, excludeId in
                guard let self else { return false }
                let docs = (try? self.list(docType: docTypeName)) ?? []
                return docs.contains { doc in
                    doc.id != excludeId && doc.fields[fieldKey] == value
                }
            },
            workflowProvider: { [weak self] workflowId in
                guard let self else { return nil }
                return try? self.loadWorkflowDefinition(workflowId: workflowId)
            },
            previousStatus: { [weak self] docTypeName, docId in
                guard let self else { return nil }
                return try? self.loadStatus(docType: docTypeName, id: docId)
            }
        )
        let errors = validationPipeline.validate(document: document, context: ctx)
        if !errors.isEmpty {
            throw DocumentEngineError.validationFailed(errors: errors)
        }
    }

    /// Load just the persisted `status` column for a document. Returns nil for
    /// brand-new documents (no row yet). Used by `WorkflowGuardStage`.
    private func loadStatus(docType: String, id: String) throws -> String? {
        try database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT status FROM documents WHERE id = ? AND doctype = ? LIMIT 1",
                arguments: [id, docType]
            )?["status"] as String?
        }
    }

    /// Load a `WorkflowDefinition` from the `workflows` table by id. Returns nil
    /// if the workflow has not been installed. Used by `WorkflowGuardStage`.
    private func loadWorkflowDefinition(workflowId: String) throws -> WorkflowDefinition? {
        let row = try database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT payload FROM workflows WHERE id = ? LIMIT 1",
                arguments: [workflowId]
            )
        }
        guard let row = row,
              let payloadString: String = row["payload"],
              let payloadData = payloadString.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkflowDefinition.self, from: payloadData)
    }

    /// Read the currently-stored `updatedAt` string and field payload for a document, if any.
    /// Used by `save(_:)` for the optimistic-concurrency check and by both save paths for
    /// computing `DocumentVersion` diffs.
    private func loadExistingState(
        docType: String,
        id: String
    ) throws -> (updatedAt: String?, fields: [String: FieldValue])? {
        let row = try database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT updatedAt, payload FROM documents WHERE id = ? AND doctype = ? LIMIT 1",
                arguments: [id, docType]
            )
        }
        guard let row = row else { return nil }
        let updatedAt: String? = row["updatedAt"]
        var fields: [String: FieldValue] = [:]
        let payloadString: String = row["payload"] ?? "{}"
        if let data = payloadString.data(using: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            fields = (try? decoder.decode([String: FieldValue].self, from: data)) ?? [:]
        }
        return (updatedAt, fields)
    }

    private func upsertDocumentRow(
        _ db: Database,
        document: Document,
        createdAt: String,
        updatedAt: String,
        syncState: SyncState,
        payloadString: String
    ) throws {
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
                createdAt,
                updatedAt,
                document.syncVersion,
                syncState.rawValue,
                document.docStatus,
                document.amendedFrom,
                payloadString
            ]
        )
    }

    private func syncChildRows(
        _ db: Database,
        document: Document,
        encoder: JSONEncoder
    ) throws {
        let currentChildIds = document.children.values.flatMap { $0 }.map { $0.id }
        if currentChildIds.isEmpty {
            try db.execute(
                sql: "DELETE FROM document_children WHERE parentId = ?",
                arguments: [document.id]
            )
        } else {
            let placeholders = currentChildIds.map { _ in "?" }.joined(separator: ",")
            var args: [any DatabaseValueConvertible] = [document.id]
            args.append(contentsOf: currentChildIds)
            try db.execute(
                sql: "DELETE FROM document_children WHERE parentId = ? AND id NOT IN (\(placeholders))",
                arguments: StatementArguments(args)
            )
        }
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
    }

    private func appendMutation(_ db: Database, mutation: MutationRecord) throws {
        let payloadString = String(data: mutation.payload, encoding: .utf8) ?? "{}"
        let ts = ISO8601DateFormatter().string(from: mutation.localTimestamp)
        try db.execute(
            sql: """
                INSERT INTO sync_queue
                    (id, type, payload, deviceId, userId, localTimestamp, syncVersion, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                mutation.id.uuidString,
                mutation.type.rawValue,
                payloadString,
                mutation.deviceId,
                mutation.userId,
                ts,
                mutation.syncVersion,
                mutation.status.rawValue
            ]
        )
    }

    /// Compute field-level diffs and insert a `DocumentVersion` row when fields changed. (ADR-024)
    private func recordDocumentVersion(
        _ db: Database,
        document: Document,
        savedAt: Date,
        savedBy: String,
        oldFields: [String: FieldValue]
    ) throws {
        let diffs = computeFieldDiffs(oldFields: oldFields, newFields: document.fields)
        guard !diffs.isEmpty else { return }

        let version = DocumentVersion(
            documentId: document.id,
            docType: document.docType,
            savedAt: savedAt,
            savedBy: savedBy,
            fieldDiffs: diffs
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let diffsData = try encoder.encode(version.fieldDiffs)
        let diffsString = String(data: diffsData, encoding: .utf8) ?? "[]"
        let savedAtStr = ISO8601DateFormatter().string(from: version.savedAt)

        try db.execute(
            sql: """
                INSERT INTO document_versions
                    (id, documentId, docType, savedAt, savedBy, fieldDiffs)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                version.id,
                version.documentId,
                version.docType,
                savedAtStr,
                version.savedBy,
                diffsString
            ]
        )
    }

    /// Decode a `DocumentVersion` from a `document_versions` row. (ADR-024, P0.8)
    private func documentVersionFromRow(_ row: Row) throws -> DocumentVersion {
        let id: String = row["id"] ?? ""
        let documentId: String = row["documentId"] ?? ""
        let docType: String = row["docType"] ?? ""
        let savedBy: String = row["savedBy"] ?? ""
        let savedAtStr: String = row["savedAt"] ?? ""
        guard !id.isEmpty, let savedAt = ISO8601DateFormatter().date(from: savedAtStr) else {
            throw DocumentEngineError.malformedRow
        }
        let diffsString: String = row["fieldDiffs"] ?? "[]"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let diffs = try decoder.decode([FieldDiff].self, from: Data(diffsString.utf8))
        return DocumentVersion(
            id: id,
            documentId: documentId,
            docType: docType,
            savedAt: savedAt,
            savedBy: savedBy,
            fieldDiffs: diffs
        )
    }

    /// ADR-013: Check that only `allowOnSubmit` fields have been modified on a submitted document.
    private func enforceSubmitImmutability(document: Document, docType: DocType) throws {
        guard let existing = try fetch(docType: document.docType, id: document.id) else {
            // New document — no immutability check needed.
            return
        }
        guard existing.docStatus == 1 else { return }

        let allowedKeys = Set(docType.fields.filter { $0.allowOnSubmit }.map { $0.key })

        // Check all keys from both old and new to detect additions, changes, and removals.
        let allKeys = Set(document.fields.keys).union(existing.fields.keys)
        for key in allKeys {
            let oldValue = existing.fields[key]
            let newValue = document.fields[key]
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
    /// for submitted documents whose link field values match the target ID using
    /// JSON extraction for precision.
    private func findLinkedSubmittedDocuments(documentId: String) throws -> [String] {
        // Gather DocTypes that have Link fields (potential linkers).
        let allDocTypes = registry.all()
        let linkingDocTypes = allDocTypes
            .filter { dt in dt.fields.contains(where: { $0.type == .link }) }

        guard !linkingDocTypes.isEmpty else { return [] }

        // Query each linking DocType for submitted documents whose link field values
        // match the target documentId using JSON extraction for precision.
        var blockingIds: [String] = []
        for dt in linkingDocTypes {
            let linkFieldKeys = dt.fields.filter { $0.type == .link }.map { $0.key }
            // Build a condition that checks each link field with json_extract.
            let conditions = linkFieldKeys.map { key in
                "json_extract(payload, '$.\(key)') = ?"
            }.joined(separator: " OR ")

            var arguments: [any DatabaseValueConvertible] = [dt.id]
            arguments.append(contentsOf: linkFieldKeys.map { _ in documentId as any DatabaseValueConvertible })
            arguments.append(documentId)

            let rows = try database.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT id FROM documents
                        WHERE docStatus = 1
                          AND doctype = ?
                          AND (\(conditions))
                          AND id != ?
                        """,
                    arguments: StatementArguments(arguments)
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

    /// Load child rows for a given parent document from the database.
    private func fetchChildren(parentId: String) throws -> [String: [ChildRow]] {
        let childRows = try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, tableName, rowIndex, payload
                    FROM document_children
                    WHERE parentId = ?
                    ORDER BY rowIndex ASC
                    """,
                arguments: [parentId]
            )
        }
        var children: [String: [ChildRow]] = [:]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for row in childRows {
            let childId: String = row["id"] ?? ""
            let tableName: String = row["tableName"] ?? ""
            let rowIndex: Int = row["rowIndex"] ?? 0
            let childPayloadString: String = row["payload"] ?? "{}"
            var fields: [String: FieldValue] = [:]
            if let payloadData = childPayloadString.data(using: .utf8) {
                fields = (try? decoder.decode([String: FieldValue].self, from: payloadData)) ?? [:]
            }
            children[tableName, default: []].append(
                ChildRow(id: childId, rowIndex: rowIndex, fields: fields)
            )
        }
        return children
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
        case validationFailed(errors: [DocumentValidationError])
        case concurrencyConflict(documentId: String)
    }

}
