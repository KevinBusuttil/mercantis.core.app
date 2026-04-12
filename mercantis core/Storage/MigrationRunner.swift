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
        public let sql: String
    }

    /// Registered migrations in version order.
    public private(set) var migrations: [Migration] = []

    public init() {}

    public mutating func register(version: Int, name: String, sql: String) {
        migrations.append(Migration(version: version, name: name, sql: sql))
    }

    // MARK: - Schema Version Tracking

    private static let schemaVersionTable = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version     INTEGER NOT NULL,
            name        TEXT    NOT NULL,
            appliedAt   TEXT    NOT NULL
        );
        """

    private func currentVersion(db: GRDBDatabase) throws -> Int {
        let rows = try db.query(
            sql: "SELECT MAX(version) FROM schema_version",
            arguments: []
        )
        if let row = rows.first, let v = row.first as? Int {
            return v
        }
        return 0
    }

    // MARK: - Run Pending Migrations

    /// Run all pending migrations against the given database pool.
    public func migrate(pool: GRDBDatabasePool) throws {
        try pool.write { db in
            // Ensure the schema_version tracking table exists.
            try db.execute(sql: MigrationRunner.schemaVersionTable)

            let current = try currentVersion(db: db)

            for migration in migrations.sorted(by: { $0.version < $1.version }) {
                guard migration.version > current else { continue }

                // Execute the migration SQL.
                try db.execute(sql: migration.sql)

                // Record that this migration has been applied.
                let now = ISO8601DateFormatter().string(from: Date())
                try db.execute(
                    sql: "INSERT INTO schema_version (version, name, appliedAt) VALUES (?, ?, ?)",
                    arguments: [migration.version, migration.name, now]
                )
            }
        }
    }

    // MARK: - Built-in Migrations

    /// Register all built-in Core migrations into the provided runner.
    public static func registerAll(into runner: inout MigrationRunner, pool: GRDBDatabasePool) {
        runner.register(version: 1, name: "initial_schema", sql: MigrationRunner.v1SQL)
    }

    // MARK: - v1 Schema

    private static let v1SQL = """
        -- DocType registry: each row is a registered DocType definition.
        CREATE TABLE IF NOT EXISTS doctypes (
            id          TEXT    PRIMARY KEY NOT NULL,
            name        TEXT    NOT NULL,
            module      TEXT    NOT NULL,
            appId       TEXT    NOT NULL,
            payload     TEXT    NOT NULL   -- JSON-encoded DocType
        );

        -- Flattened field definitions for efficient lookup by fieldKey.
        CREATE TABLE IF NOT EXISTS fields (
            docTypeId   TEXT    NOT NULL REFERENCES doctypes(id) ON DELETE CASCADE,
            fieldKey    TEXT    NOT NULL,
            fieldType   TEXT    NOT NULL,
            payload     TEXT    NOT NULL,   -- JSON-encoded FieldDefinition
            PRIMARY KEY (docTypeId, fieldKey)
        );

        -- Core document store. (ADR-002)
        -- system columns are indexed; user-defined field values live in payload JSON.
        CREATE TABLE IF NOT EXISTS documents (
            id              TEXT    PRIMARY KEY NOT NULL,
            doctype         TEXT    NOT NULL,
            company         TEXT    NOT NULL DEFAULT '',
            status          TEXT    NOT NULL DEFAULT '',
            createdAt       TEXT    NOT NULL,
            updatedAt       TEXT    NOT NULL,
            syncVersion     INTEGER NOT NULL DEFAULT 0,
            syncState       TEXT    NOT NULL DEFAULT 'local',
            payload         TEXT    NOT NULL DEFAULT '{}'   -- JSON field values
        );

        CREATE INDEX IF NOT EXISTS idx_documents_doctype    ON documents(doctype);
        CREATE INDEX IF NOT EXISTS idx_documents_status     ON documents(status);
        CREATE INDEX IF NOT EXISTS idx_documents_syncState  ON documents(syncState);

        -- Child table rows linked to a parent document. (ADR-002)
        CREATE TABLE IF NOT EXISTS document_children (
            id              TEXT    PRIMARY KEY NOT NULL,
            parentId        TEXT    NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            parentDocType   TEXT    NOT NULL,
            tableName       TEXT    NOT NULL,   -- child DocType / table field key
            rowIndex        INTEGER NOT NULL DEFAULT 0,
            payload         TEXT    NOT NULL DEFAULT '{}'   -- JSON field values
        );

        CREATE INDEX IF NOT EXISTS idx_children_parent ON document_children(parentId);

        -- Mutation log / sync queue. Every write appends one row. (ADR-005)
        CREATE TABLE IF NOT EXISTS sync_queue (
            id              TEXT    PRIMARY KEY NOT NULL,   -- UUID
            type            TEXT    NOT NULL,
            payload         TEXT    NOT NULL,               -- JSON mutation payload
            deviceId        TEXT    NOT NULL,
            userId          TEXT    NOT NULL,
            localTimestamp  TEXT    NOT NULL,
            syncVersion     INTEGER NOT NULL DEFAULT 0,
            status          TEXT    NOT NULL DEFAULT 'pending'
        );

        CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status);

        -- Immutable audit log. (ADR-006 Append-Only policy)
        CREATE TABLE IF NOT EXISTS audit_log (
            id              TEXT    PRIMARY KEY NOT NULL,
            documentId      TEXT    NOT NULL,
            docType         TEXT    NOT NULL,
            userId          TEXT    NOT NULL,
            action          TEXT    NOT NULL,
            timestamp       TEXT    NOT NULL,
            payload         TEXT    NOT NULL DEFAULT '{}'
        );

        CREATE INDEX IF NOT EXISTS idx_audit_log_document ON audit_log(documentId);

        -- Installed app manifests. (ADR-004)
        CREATE TABLE IF NOT EXISTS apps (
            id              TEXT    PRIMARY KEY NOT NULL,
            name            TEXT    NOT NULL,
            version         TEXT    NOT NULL,
            installedAt     TEXT    NOT NULL,
            payload         TEXT    NOT NULL   -- JSON-encoded AppManifest
        );

        -- Workflow definitions. (ADR-004)
        CREATE TABLE IF NOT EXISTS workflows (
            id              TEXT    PRIMARY KEY NOT NULL,
            name            TEXT    NOT NULL,
            docType         TEXT    NOT NULL,
            appId           TEXT    NOT NULL,
            payload         TEXT    NOT NULL   -- JSON-encoded WorkflowDefinition
        );
        """
}
