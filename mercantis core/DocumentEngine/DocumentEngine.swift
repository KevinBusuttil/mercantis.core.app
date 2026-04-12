//
//  DocumentEngine.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Handles all CRUD operations on documents.
/// Every persistent write atomically appends a MutationRecord to the sync queue. (ADR-002, ADR-005)
///
/// Direct SQLite writes that bypass the DocumentEngine are prohibited. (ADR-005)
public final class DocumentEngine {

    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    /// Create or update a document. Appends an `upsertDocument` mutation atomically.
    public func save(_ document: Document) throws {
        // TODO: Validate document against its DocType metadata via SchemaValidator
        // TODO: Write to SQLite document table + append MutationRecord in same transaction
    }

    /// Delete a document. Appends a `deleteDocument` mutation atomically.
    public func delete(docType: String, id: String) throws {
        // TODO: Delete from SQLite + append MutationRecord in same transaction
    }

    /// Fetch a single document by type and ID.
    public func fetch(docType: String, id: String) throws -> Document? {
        // TODO: Query SQLite document table
        return nil
    }

    /// Fetch all documents of a given type, with optional filters.
    public func list(docType: String, filters: [String: FieldValue]? = nil) throws -> [Document] {
        // TODO: Query SQLite with optional WHERE clauses
        return []
    }
}
