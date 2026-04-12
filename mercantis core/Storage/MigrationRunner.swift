//
//  MigrationRunner.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Runs versioned, forward-only SQL migrations against the database.
/// Every migration is a named, tested, forward-only script. (ADR-002)
public struct MigrationRunner {

    /// A single named migration.
    public struct Migration {
        public let version: Int
        public let name: String
        public let migrate: () throws -> Void
    }

    /// Registered migrations in order.
    public private(set) var migrations: [Migration] = []

    public init() {}

    public mutating func register(version: Int, name: String, migrate: @escaping () throws -> Void) {
        migrations.append(Migration(version: version, name: name, migrate: migrate))
    }

    /// Run all pending migrations.
    public func migrate() throws {
        // TODO: Track current version in a `schema_version` table
        // TODO: Execute each pending migration in a transaction
    }
}
