//
//  DocumentEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

/// A node in a tree-structured DocType's hierarchy. (W8)
public struct TreeNode: Sendable {
    public let document: Document
    public let children: [TreeNode]

    public init(document: Document, children: [TreeNode]) {
        self.document = document
        self.children = children
    }
}

/// One entry in a `DocumentEngine.list(...)` ORDER BY chain. (P2.5)
///
/// `fieldKey` may name either a `documents`-table system column (`id`,
/// `status`, `createdAt`, `updatedAt`, `syncVersion`, `docStatus`, ...) or a
/// user-defined field key. System-column and indexed-field sorts are pushed
/// to SQL; the remainder is sorted in memory after the row fetch.
public struct ListSort: Sendable, Equatable {
    public enum Direction: String, Sendable, Equatable {
        case ascending
        case descending
    }

    public let fieldKey: String
    public let direction: Direction

    public init(fieldKey: String, direction: Direction = .ascending) {
        self.fieldKey = fieldKey
        self.direction = direction
    }
}

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
    private let namingService: NamingService
    private let deviceId: String
    private let userId: String

    public init(
        database: MercantisDatabase,
        registry: MetadataRegistry,
        deviceId: String,
        userId: String,
        eventEmitter: EventEmitter = EventEmitter(),
        validationPipeline: ValidationPipeline = ValidationPipeline(),
        namingService: NamingService = NamingService()
    ) {
        self.database = database
        self.registry = registry
        self.validator = SchemaValidator()
        self.eventEmitter = eventEmitter
        self.validationPipeline = validationPipeline
        self.namingService = namingService
        self.deviceId = deviceId
        self.userId = userId
    }

    // MARK: - Cross-document lookup (ADR-029, P2.2)

    /// Read-through cache around the engine's own `lookup(docType:name:field:)`.
    /// Cached entries are dropped whenever the engine publishes a save/delete/submit/cancel
    /// event for the affected `(docType, id)` pair.
    public private(set) lazy var lookupCache: CachingDocumentLookupResolver = {
        CachingDocumentLookupResolver(base: self, eventEmitter: eventEmitter)
    }()

    /// Expression evaluator pre-wired with the engine's `lookupCache`.
    /// `DocumentEngine.list`'s `whereExpression` runs against this evaluator.
    public private(set) lazy var listExpressionEvaluator: ExpressionEvaluator = {
        ExpressionEvaluator(lookupResolver: lookupCache)
    }()

    // MARK: - Save

    /// Create or update a document. Appends an `upsertDocument` mutation atomically.
    ///
    /// If `document.id` is empty, `NamingService` resolves it from the DocType's
    /// `autoname` (defaulting to UUIDv7). (P1.1 / ADR-014)
    @discardableResult
    public func save(_ document: Document, userSuppliedName: String? = nil) throws -> Document {
        var document = try assigningNameIfNeeded(document, userSuppliedName: userSuppliedName)

        let existing = try loadExistingState(docType: document.docType, id: document.id)

        if let docType = registry.get(document.docType) {
            try validator.validate(docType)
            document = try runValidationPipeline(on: document, docType: docType, isNew: existing == nil)

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
        return document
    }

    // MARK: - Naming (P1.1 / ADR-014)

    /// If `document.id` is empty, resolve it via `NamingService` and return a
    /// copy of the document with the assigned ID. Otherwise returns the input unchanged.
    private func assigningNameIfNeeded(
        _ document: Document,
        userSuppliedName: String?
    ) throws -> Document {
        guard document.id.isEmpty else { return document }
        guard let docType = registry.get(document.docType) else {
            throw DocumentEngineError.docTypeNotFound(document.docType)
        }
        let context = NamingContext(
            userSuppliedName: userSuppliedName,
            now: Date(),
            counterProvider: { [database] seriesKey in
                try Self.reserveCounter(in: database, seriesKey: seriesKey)
            }
        )
        let resolvedId = try namingService.resolve(
            docType: docType,
            document: document,
            context: context
        )
        return Document(
            id: resolvedId,
            docType: document.docType,
            company: document.company,
            status: document.status,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt,
            syncVersion: document.syncVersion,
            syncState: document.syncState,
            docStatus: document.docStatus,
            amendedFrom: document.amendedFrom,
            parentID: document.parentID,
            fields: document.fields,
            children: document.children
        )
    }

    /// Atomically increment and return the next counter value for a naming-series key.
    private static func reserveCounter(
        in database: MercantisDatabase,
        seriesKey: String
    ) throws -> Int {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO naming_counters (seriesKey, value) VALUES (?, 1)
                    ON CONFLICT(seriesKey) DO UPDATE SET value = value + 1
                    """,
                arguments: [seriesKey]
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM naming_counters WHERE seriesKey = ?",
                arguments: [seriesKey]
            )
            let value: Int = row?["value"] ?? 0
            return value
        }
    }

    // MARK: - Apply Remote (ADR-005, P0.2)

    /// Apply a remote upsert received via the sync engine. Does not append a new
    /// MutationRecord; forces syncState to .synced. (ADR-005)
    public func applyRemote(_ document: Document, from mutation: MutationRecord) throws {
        var doc = document
        doc.syncVersion = mutation.syncVersion
        doc.syncState = .synced

        let existing = try loadExistingState(docType: doc.docType, id: doc.id)

        if let docType = registry.get(doc.docType) {
            try validator.validate(docType)
            doc = try runValidationPipeline(on: doc, docType: docType, isNew: existing == nil)
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

    /// Cancel a submitted document, transitioning it from Submitted (1) to Cancelled (2).
    /// Rejects if any downstream submitted document holds a Link field pointing here. (ADR-013)
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

    /// Amend a cancelled document by creating a new Draft copy. `parentID` is not
    /// inherited — the amended copy is placed at the tree root. (ADR-013)
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
            parentID: nil,
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
                           syncVersion, syncState, docStatus, amendedFrom, parentId, payload
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

    /// Fetch documents of a given type with optional filters, sort, paging, and a
    /// boolean expression predicate. (P2.5)
    public func list(
        docType: String,
        filters: [String: FieldValue]? = nil,
        whereExpression: String? = nil,
        sortBy: [ListSort]? = nil,
        limit: Int? = nil,
        offset: Int = 0
    ) throws -> [Document] {
        let resolvedDocType = registry.get(docType)
        let indexedFieldKeys: Set<String> = resolvedDocType.map { Set($0.indexes.map(\.fieldKey)) } ?? []
        let userDeclaredFieldKeys: Set<String> = resolvedDocType.map { Set($0.fields.map(\.key)) } ?? []

        var sqlClauses: [String] = ["doctype = ?"]
        var arguments: [any DatabaseValueConvertible] = [docType]
        var inMemoryFilters: [String: FieldValue] = [:]

        for (key, value) in filters ?? [:] {
            if let fragment = sqlFilterFragment(
                forKey: key,
                value: value,
                indexedFieldKeys: indexedFieldKeys,
                userDeclaredFieldKeys: userDeclaredFieldKeys
            ) {
                sqlClauses.append(fragment.sql)
                arguments.append(contentsOf: fragment.arguments)
            } else {
                inMemoryFilters[key] = value
            }
        }

        let trimmedWhere = whereExpression?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeWhereExpression: String? = (trimmedWhere?.isEmpty ?? true) ? nil : trimmedWhere

        let sortPushdown = sqlOrderByClause(
            for: sortBy,
            indexedFieldKeys: indexedFieldKeys,
            userDeclaredFieldKeys: userDeclaredFieldKeys
        )
        let needsInMemoryWork = !inMemoryFilters.isEmpty
            || activeWhereExpression != nil
            || (sortBy != nil && sortPushdown == nil)
        let pagingPushedToSQL = !needsInMemoryWork && limit != nil

        var sql = """
            SELECT id, doctype, company, status, createdAt, updatedAt,
                   syncVersion, syncState, docStatus, amendedFrom, parentId, payload
            FROM documents
            WHERE \(sqlClauses.joined(separator: " AND "))
            ORDER BY \(sortPushdown ?? "updatedAt DESC")
            """

        if pagingPushedToSQL, let limit = limit {
            sql += "\nLIMIT ? OFFSET ?"
            arguments.append(limit)
            arguments.append(offset)
        }

        let rows = try database.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }

        var documents = try rows.map { try documentFromRow($0) }

        for i in documents.indices {
            documents[i].children = try fetchChildren(parentId: documents[i].id)
        }

        if !inMemoryFilters.isEmpty {
            documents = documents.filter { doc in
                inMemoryFilters.allSatisfy { (key, value) in
                    doc.fields[key] == value
                }
            }
        }

        if let expression = activeWhereExpression {
            let evaluator = listExpressionEvaluator
            documents = documents.filter { doc in
                (try? evaluator.evaluateBool(expression: expression, context: doc.fields)) ?? false
            }
        }

        if needsInMemoryWork, let sortBy = sortBy, !sortBy.isEmpty {
            documents.sort { applySort(sortBy, lhs: $0, rhs: $1) }
        }

        if !pagingPushedToSQL, limit != nil || offset > 0 {
            let start = min(max(offset, 0), documents.count)
            let end: Int
            if let limit = limit {
                end = min(start + max(limit, 0), documents.count)
            } else {
                end = documents.count
            }
            documents = Array(documents[start..<end])
        }

        return documents
    }

    // MARK: - Tree (W8)

    /// Fetch all documents of a tree DocType structured as a forest.
    /// Root nodes are documents whose `parentID` is nil.
    public func fetchTree(docType: String) throws -> [TreeNode] {
        let all = try list(docType: docType)
        return buildTree(from: all)
    }

    /// Fetch immediate children of a document in a tree DocType.
    public func children(of parentID: String, in docType: String) throws -> [Document] {
        try list(docType: docType, filters: ["parentID": .string(parentID)])
    }

    private func buildTree(from documents: [Document]) -> [TreeNode] {
        let byParent = Dictionary(grouping: documents) { $0.parentID ?? "" }
        func nodes(under parentID: String) -> [TreeNode] {
            (byParent[parentID] ?? []).map { doc in
                TreeNode(document: doc, children: nodes(under: doc.id))
            }
        }
        return nodes(under: "")
    }

    // MARK: - List helpers (P2.5)

    private struct SQLFilterFragment {
        let sql: String
        let arguments: [any DatabaseValueConvertible]
    }

    /// Map a system column / indexed JSON field filter to a SQL fragment, or
    /// return `nil` to defer the filter to the in-memory pass.
    private func sqlFilterFragment(
        forKey key: String,
        value: FieldValue,
        indexedFieldKeys: Set<String>,
        userDeclaredFieldKeys: Set<String>
    ) -> SQLFilterFragment? {
        if let column = systemColumn(for: key, userDeclaredFieldKeys: userDeclaredFieldKeys) {
            if column == "doctype" { return SQLFilterFragment(sql: "doctype = ?", arguments: [databaseValue(for: value) ?? ""]) }
            if case .null = value {
                return SQLFilterFragment(sql: "\(column) IS NULL", arguments: [])
            }
            guard let arg = databaseValue(for: value) else { return nil }
            return SQLFilterFragment(sql: "\(column) = ?", arguments: [arg])
        }
        if indexedFieldKeys.contains(key) {
            if case .null = value {
                return SQLFilterFragment(
                    sql: "json_extract(payload, '$.\(key)') IS NULL",
                    arguments: []
                )
            }
            guard let arg = databaseValue(for: value) else { return nil }
            return SQLFilterFragment(
                sql: "json_extract(payload, '$.\(key)') = ?",
                arguments: [arg]
            )
        }
        return nil
    }

    /// Build a SQL ORDER BY clause when every sort key is SQL-pushable.
    /// Returns `nil` when at least one key requires an in-memory sort.
    private func sqlOrderByClause(
        for sortBy: [ListSort]?,
        indexedFieldKeys: Set<String>,
        userDeclaredFieldKeys: Set<String>
    ) -> String? {
        guard let sortBy = sortBy, !sortBy.isEmpty else { return nil }
        var fragments: [String] = []
        for sort in sortBy {
            let direction = sort.direction == .ascending ? "ASC" : "DESC"
            if let column = systemColumn(for: sort.fieldKey, userDeclaredFieldKeys: userDeclaredFieldKeys) {
                fragments.append("\(column) \(direction)")
            } else if indexedFieldKeys.contains(sort.fieldKey) {
                fragments.append("json_extract(payload, '$.\(sort.fieldKey)') \(direction)")
            } else {
                return nil
            }
        }
        return fragments.joined(separator: ", ")
    }

    /// Map a public field key to its `documents`-table column. User-declared field
    /// keys always win over system columns of the same name.
    private func systemColumn(for key: String, userDeclaredFieldKeys: Set<String>) -> String? {
        guard !userDeclaredFieldKeys.contains(key) else { return nil }
        switch key {
        case "id", "doctype", "company", "status",
             "createdAt", "updatedAt", "syncVersion", "syncState",
             "docStatus", "amendedFrom":
            return key
        case "parentID":
            return "parentId"
        default:
            return nil
        }
    }

    /// Convert a primitive `FieldValue` to a SQL argument. Tagged cases return `nil`.
    private func databaseValue(for value: FieldValue) -> (any DatabaseValueConvertible)? {
        switch value {
        case .string(let s): return s
        case .int(let i):    return i
        case .double(let d): return d
        case .bool(let b):   return b ? 1 : 0
        case .null:          return nil
        case .date, .dateTime, .data, .array:
            return nil
        }
    }

    /// In-memory comparator across an ordered `[ListSort]` chain. Stable on ties.
    private func applySort(_ sortBy: [ListSort], lhs: Document, rhs: Document) -> Bool {
        for sort in sortBy {
            let lhsValue = sortValue(for: sort.fieldKey, in: lhs)
            let rhsValue = sortValue(for: sort.fieldKey, in: rhs)
            switch compareForSort(lhsValue, rhsValue) {
            case .orderedAscending:  return sort.direction == .ascending
            case .orderedDescending: return sort.direction == .descending
            case .orderedSame:       continue
            }
        }
        return false
    }

    /// Read a sortable value from a document. User-declared fields win over system columns.
    private func sortValue(for key: String, in document: Document) -> FieldValue? {
        if let userValue = document.fields[key] { return userValue }
        switch key {
        case "id":          return .string(document.id)
        case "doctype":     return .string(document.docType)
        case "company":     return .string(document.company)
        case "status":      return .string(document.status)
        case "createdAt":   return .dateTime(document.createdAt)
        case "updatedAt":   return .dateTime(document.updatedAt)
        case "syncVersion": return .int(Int(document.syncVersion))
        case "syncState":   return .string(document.syncState.rawValue)
        case "docStatus":   return .int(document.docStatus)
        case "amendedFrom": return document.amendedFrom.map { .string($0) }
        case "parentID":    return document.parentID.map { .string($0) }
        default:            return nil
        }
    }

    private func compareForSort(_ a: FieldValue?, _ b: FieldValue?) -> ComparisonResult {
        func isMissing(_ value: FieldValue?) -> Bool {
            switch value {
            case nil, .some(.null): return true
            default: return false
            }
        }
        let aMissing = isMissing(a)
        let bMissing = isMissing(b)
        if aMissing && bMissing { return .orderedSame }
        if aMissing { return .orderedDescending }
        if bMissing { return .orderedAscending }
        guard let a = a, let b = b else { return .orderedSame }

        if let an = numericForSort(a), let bn = numericForSort(b) {
            if an < bn { return .orderedAscending }
            if an > bn { return .orderedDescending }
            return .orderedSame
        }

        let aStr = stringForSort(a)
        let bStr = stringForSort(b)
        if aStr < bStr { return .orderedAscending }
        if aStr > bStr { return .orderedDescending }
        return .orderedSame
    }

    private func numericForSort(_ value: FieldValue) -> Double? {
        switch value {
        case .int(let i):    return Double(i)
        case .double(let d): return d
        case .bool(let b):   return b ? 1 : 0
        case .date(let d), .dateTime(let d):
            return d.timeIntervalSince1970
        default:
            return nil
        }
    }

    private func stringForSort(_ value: FieldValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return String(d)
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return ""
        case .date(let d), .dateTime(let d):
            return ISO8601DateFormatter().string(from: d)
        case .data(let d):   return d.base64EncodedString()
        case .array:         return ""
        }
    }

    // MARK: - Versions (ADR-024, P0.8)

    /// Return the full append-only version history for a document, oldest first.
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

    /// Return the document version in effect at `timestamp`.
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

    private func runValidationPipeline(
        on document: Document,
        docType: DocType,
        isNew: Bool
    ) throws -> Document {
        var document = document
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
        let errors = validationPipeline.validate(document: &document, context: ctx)
        if !errors.isEmpty {
            throw DocumentEngineError.validationFailed(errors: errors)
        }
        return document
    }

    private func loadStatus(docType: String, id: String) throws -> String? {
        try database.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT status FROM documents WHERE id = ? AND doctype = ? LIMIT 1",
                arguments: [id, docType]
            )?["status"] as String?
        }
    }

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
                    (id, doctype, company, status, createdAt, updatedAt, syncVersion, syncState, docStatus, amendedFrom, parentId, payload)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    company     = excluded.company,
                    status      = excluded.status,
                    updatedAt   = excluded.updatedAt,
                    syncVersion = excluded.syncVersion,
                    syncState   = excluded.syncState,
                    docStatus   = excluded.docStatus,
                    amendedFrom = excluded.amendedFrom,
                    parentId    = excluded.parentId,
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
                document.parentID,
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

    private func enforceSubmitImmutability(document: Document, docType: DocType) throws {
        guard let existing = try fetch(docType: document.docType, id: document.id) else { return }
        guard existing.docStatus == 1 else { return }

        let allowedKeys = Set(docType.fields.filter { $0.allowOnSubmit }.map { $0.key })

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

    private func findLinkedSubmittedDocuments(documentId: String) throws -> [String] {
        let allDocTypes = registry.all()
        let linkingDocTypes = allDocTypes
            .filter { dt in dt.fields.contains(where: { $0.type == .link }) }

        guard !linkingDocTypes.isEmpty else { return [] }

        var blockingIds: [String] = []
        for dt in linkingDocTypes {
            let linkFieldKeys = dt.fields.filter { $0.type == .link }.map { $0.key }
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
        let parentID: String? = row["parentId"]
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
            parentID: parentID,
            fields: fields,
            children: [:]
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

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

// MARK: - DocumentLookupResolver conformance (ADR-029, P2.2)

extension DocumentEngine: DocumentLookupResolver {
    public func lookup(docType: String, name: String, field: String) throws -> FieldValue? {
        guard let document = try fetch(docType: docType, id: name) else { return nil }
        return document.fields[field]
    }
}
