//
//  MercantisDatabase.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation

/// Central database manager for Mercantis Core.
/// Wraps SQLite via GRDB and owns all schema migrations.
/// All persistent reads and writes in Core MUST go through this class. (ADR-002)
public final class MercantisDatabase {

    /// The URL of the SQLite database file.
    public let databaseURL: URL

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        // TODO: Open GRDB DatabasePool at databaseURL
        // TODO: Run MigrationRunner.migrate()
    }
}
