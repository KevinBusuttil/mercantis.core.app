//
//  MercantisDatabase.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

// DEPENDENCY: This file requires the GRDB Swift package.
// Package URL: https://github.com/groue/GRDB.swift  Version: >= 6.0.0
//
import GRDB

import Foundation

/// Central database manager for Mercantis Core.
/// Wraps SQLite via GRDB and owns all schema migrations.
/// All persistent reads and writes in Core MUST go through this class. (ADR-002)
public final class MercantisDatabase {

    /// The URL of the SQLite database file.
    public let databaseURL: URL

    /// The underlying GRDB database pool.
    private let pool: DatabasePool

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL

        // Open (or create) the SQLite database at the given URL.
        let pool = try DatabasePool(path: databaseURL.path)
        self.pool = pool

        // Run all pending schema migrations on startup.
        var runner = MigrationRunner()
        MigrationRunner.registerAll(into: &runner, pool: pool)
        try runner.migrate(pool: pool)
    }

    // MARK: - Read / Write

    /// Execute a read-only block on the database.
    /// Multiple concurrent reads are allowed.
    public func read<T>(_ block: (Database) throws -> T) throws -> T {
        return try pool.read(block)
    }

    /// Execute a write block on the database inside a transaction.
    public func write<T>(_ block: (Database) throws -> T) throws -> T {
        return try pool.write(block)
    }
}
