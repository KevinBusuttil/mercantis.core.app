//
//  MetadataRegistry.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

/// In-memory DocType registry backed by the `doctypes` table in SQLite.
///
/// All DocType lookups during document validation and rendering go through
/// this registry. DocTypes are loaded from the database on first access and
/// cached in memory. (ADR-003)
public final class MetadataRegistry: @unchecked Sendable {

    private var cache: [String: DocType] = [:]
    private let lock = NSLock()
    private let database: MercantisDatabase

    public init(database: MercantisDatabase) {
        self.database = database
    }

    // MARK: - Public API

    /// Register (or replace) a DocType in the in-memory cache and persist it to the database.
    public func register(_ docType: DocType) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadData = try encoder.encode(docType)
        guard let payloadString = String(data: payloadData, encoding: .utf8) else {
            throw MetadataRegistryError.encodingFailed(docTypeId: docType.id)
        }

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO doctypes (id, name, module, appId, payload)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name    = excluded.name,
                        module  = excluded.module,
                        appId   = excluded.appId,
                        payload = excluded.payload
                    """,
                arguments: [docType.id, docType.name, docType.module, docType.appId, payloadString]
            )
        }

        lock.lock()
        cache[docType.id] = docType
        lock.unlock()
    }

    /// Retrieve a DocType by its identifier. Checks the in-memory cache first,
    /// then falls back to the database.
    public func get(_ id: String) -> DocType? {
        lock.lock()
        if let cached = cache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        // Attempt to load from database.
        guard let docType = try? loadFromDatabase(id: id) else { return nil }

        lock.lock()
        cache[id] = docType
        lock.unlock()
        return docType
    }

    /// Return all registered DocTypes.
    public func all() -> [DocType] {
        // Load everything from the database to ensure we have the full list.
        let dbDocTypes = (try? loadAllFromDatabase()) ?? []

        lock.lock()
        for docType in dbDocTypes {
            cache[docType.id] = docType
        }
        let result = Array(cache.values)
        lock.unlock()
        return result
    }

    /// Remove a DocType from the registry (e.g. when an app is uninstalled).
    public func remove(_ id: String) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM doctypes WHERE id = ?", arguments: [id])
        }
        lock.lock()
        cache.removeValue(forKey: id)
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func loadFromDatabase(id: String) throws -> DocType? {
        let row = try database.read { db in
            try Row.fetchOne(db, sql: "SELECT payload FROM doctypes WHERE id = ?", arguments: [id])
        }
        guard let row = row,
              let payloadString: String = row[0],
              let payloadData = payloadString.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DocType.self, from: payloadData)
    }

    private func loadAllFromDatabase() throws -> [DocType] {
        let rows = try database.read { db in
            try Row.fetchAll(db, sql: "SELECT payload FROM doctypes", arguments: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try rows.compactMap { row -> DocType? in
            guard let payloadString: String = row[0],
                  let payloadData = payloadString.data(using: .utf8) else { return nil }
            return try decoder.decode(DocType.self, from: payloadData)
        }
    }

    // MARK: - Errors

    public enum MetadataRegistryError: Error, Sendable {
        case encodingFailed(docTypeId: String)
    }
}
