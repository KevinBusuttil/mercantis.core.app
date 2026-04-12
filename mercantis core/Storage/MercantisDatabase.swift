//
//  MercantisDatabase.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

// DEPENDENCY: This file requires the GRDB Swift package.
// Add it via Xcode → File → Add Package Dependencies…
// URL: https://github.com/groue/GRDB.swift
// Version: >= 6.0.0
// After adding the package, uncomment the `import GRDB` line below
// and remove the `GRDBStub` section at the bottom of this file.
//
// import GRDB

import Foundation

/// Central database manager for Mercantis Core.
/// Wraps SQLite via GRDB and owns all schema migrations.
/// All persistent reads and writes in Core MUST go through this class. (ADR-002)
public final class MercantisDatabase {

    /// The URL of the SQLite database file.
    public let databaseURL: URL

    /// The underlying GRDB database pool. Typed as `Any` until the GRDB package
    /// is added; replace with `DatabasePool` once the import is active.
    private let pool: GRDBDatabasePool

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        // Open (or create) the SQLite database at the given URL.
        let pool = try GRDBDatabasePool(path: databaseURL.path)
        self.pool = pool

        // Run all pending schema migrations on startup.
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)
    }

    // MARK: - Read / Write

    /// Execute a read-only block on the database.
    /// Multiple concurrent reads are allowed.
    public func read<T>(_ block: (GRDBDatabase) throws -> T) throws -> T {
        return try pool.read(block)
    }

    /// Execute a write block on the database inside a transaction.
    public func write<T>(_ block: (GRDBDatabase) throws -> T) throws -> T {
        return try pool.write(block)
    }
}

// MARK: - GRDB Stub (remove once GRDB package is added)
//
// These stubs let the project compile before the GRDB package is integrated.
// They mirror the GRDB API surface used by this file and MigrationRunner.

/// Stub representing a GRDB `Database` connection passed into read/write blocks.
public final class GRDBDatabase {
    /// Execute an SQL statement.
    public func execute(sql: String, arguments: [Any?] = []) throws {
        // no-op until GRDB is linked
    }

    /// Execute a SELECT and return rows as arrays of optional values.
    public func query(sql: String, arguments: [Any?] = []) throws -> [[Any?]] {
        return []
    }
}

/// Stub representing a GRDB `DatabasePool`.
public final class GRDBDatabasePool {
    public let path: String

    public init(path: String) throws {
        self.path = path
    }

    public func read<T>(_ block: (GRDBDatabase) throws -> T) throws -> T {
        return try block(GRDBDatabase())
    }

    public func write<T>(_ block: (GRDBDatabase) throws -> T) throws -> T {
        return try block(GRDBDatabase())
    }
}
