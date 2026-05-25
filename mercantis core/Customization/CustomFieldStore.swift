//
//  CustomFieldStore.swift
//  mercantis core
//
//  Persistence for end-user `CustomField` rows added on top of a base
//  DocType. (ADR-021)
//
//  The store is the source of truth that hydrates
//  `MetaComposer.setCustomFields(_:for:)` at boot — without that load step
//  custom fields would only live in memory and disappear on relaunch.
//

import Foundation
import GRDB

/// CRUD over the `custom_fields` SQLite table.
public final class CustomFieldStore {

    private let database: MercantisDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(database: MercantisDatabase) {
        self.database = database
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - Reads

    /// All custom fields, grouped by DocType id. Used at app start to seed
    /// the `MetaComposer`.
    public func loadAll() throws -> [String: [CustomField]] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, doctype, insert_after, field_definition
                FROM custom_fields
                ORDER BY doctype, created_at
                """)
            var grouped: [String: [CustomField]] = [:]
            for row in rows {
                let field = try decode(row: row)
                grouped[field.docType, default: []].append(field)
            }
            return grouped
        }
    }

    /// Custom fields for one DocType, ordered by creation time.
    public func list(forDocType docTypeId: String) throws -> [CustomField] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, doctype, insert_after, field_definition
                FROM custom_fields
                WHERE doctype = ?
                ORDER BY created_at
                """, arguments: [docTypeId])
            return try rows.map(decode(row:))
        }
    }

    // MARK: - Writes

    /// Insert a new custom field. Fails if `(docType, field_key)` already
    /// exists (the UNIQUE constraint guards against duplicate keys).
    public func add(_ field: CustomField) throws {
        let payload = try jsonString(for: field.fieldDefinition)
        let now = ISO8601DateFormatter().string(from: Date())
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO custom_fields
                        (id, doctype, field_key, insert_after, field_definition, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    field.id,
                    field.docType,
                    field.fieldDefinition.key,
                    nullIfEmpty(field.insertAfter),
                    payload,
                    now,
                    now
                ]
            )
        }
    }

    /// Replace an existing custom field's definition and/or position.
    public func update(_ field: CustomField) throws {
        let payload = try jsonString(for: field.fieldDefinition)
        let now = ISO8601DateFormatter().string(from: Date())
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE custom_fields
                       SET field_key = ?,
                           insert_after = ?,
                           field_definition = ?,
                           updated_at = ?
                     WHERE id = ?
                    """,
                arguments: [
                    field.fieldDefinition.key,
                    nullIfEmpty(field.insertAfter),
                    payload,
                    now,
                    field.id
                ]
            )
        }
    }

    /// Remove the field with the given id.
    public func remove(id: String) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM custom_fields WHERE id = ?",
                arguments: [id]
            )
        }
    }

    // MARK: - Helpers

    private func decode(row: Row) throws -> CustomField {
        let id: String = row["id"]
        let docType: String = row["doctype"]
        let insertAfter: String? = row["insert_after"]
        let payload: String = row["field_definition"]
        guard let data = payload.data(using: .utf8) else {
            throw CustomFieldStoreError.invalidPayload(id: id)
        }
        let definition = try decoder.decode(FieldDefinition.self, from: data)
        return CustomField(
            id: id,
            docType: docType,
            fieldDefinition: definition,
            insertAfter: insertAfter
        )
    }

    private func jsonString(for definition: FieldDefinition) throws -> String {
        let data = try encoder.encode(definition)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func nullIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

public enum CustomFieldStoreError: Error, LocalizedError {
    case invalidPayload(id: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let id):
            return "Custom field \(id) has an unreadable field_definition payload."
        }
    }
}
