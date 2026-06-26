//
//  MigrationRunner.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import Foundation
import GRDB

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

    private func currentVersion(db: Database) throws -> Int {
        if let row = try Row.fetchOne(db, sql: "SELECT MAX(version) FROM schema_version"),
           let v: Int = row[0] {
            return v
        }
        return 0
    }

    // MARK: - Run Pending Migrations

    /// Run all pending migrations against the given database pool.
    public func migrate(pool: DatabasePool) throws {
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
    public static func registerAll(into runner: inout MigrationRunner, pool: DatabasePool) {
        runner.register(version: 1, name: "initial_schema", sql: MigrationRunner.v1SQL)
        runner.register(version: 2, name: "add_doc_status_columns", sql: MigrationRunner.v2SQL)
        runner.register(version: 3, name: "add_document_versions", sql: MigrationRunner.v3SQL)
        runner.register(version: 4, name: "add_sync_state", sql: MigrationRunner.v4SQL)
        runner.register(version: 5, name: "add_naming_counters", sql: MigrationRunner.v5SQL)
        runner.register(version: 6, name: "add_scheduler_state", sql: MigrationRunner.v6SQL)
        runner.register(version: 7, name: "add_tree_parent", sql: MigrationRunner.v7SQL)
        runner.register(version: 8, name: "add_workflow_transitions", sql: MigrationRunner.v8SQL)
        runner.register(version: 9, name: "add_naming_counter_blocks", sql: MigrationRunner.v9SQL)
        runner.register(version: 10, name: "add_attachments", sql: MigrationRunner.v10SQL)
        runner.register(version: 11, name: "add_notification_log", sql: MigrationRunner.v11SQL)
        runner.register(version: 12, name: "add_custom_fields", sql: MigrationRunner.v12SQL)
        runner.register(version: 13, name: "add_posting_batches", sql: MigrationRunner.v13SQL)
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

    // MARK: - v2 Schema — docStatus + amendedFrom

    private static let v2SQL = """
        -- ADR-013: Submit / Cancel / Amend lifecycle columns.
        ALTER TABLE documents ADD COLUMN docStatus INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE documents ADD COLUMN amendedFrom TEXT;
        """

    // MARK: - v3 Schema — document_versions (ADR-024)

    private static let v3SQL = """
        -- ADR-024: Document versioning and field-level diff tracking.
        -- Append-only table: records are never modified or deleted.
        CREATE TABLE IF NOT EXISTS document_versions (
            id              TEXT    PRIMARY KEY NOT NULL,
            documentId      TEXT    NOT NULL,
            docType         TEXT    NOT NULL,
            savedAt         TEXT    NOT NULL,
            savedBy         TEXT    NOT NULL,
            fieldDiffs      TEXT    NOT NULL DEFAULT '[]'   -- JSON-encoded [FieldDiff]
        );

        CREATE INDEX IF NOT EXISTS idx_document_versions_document ON document_versions(documentId);
        CREATE INDEX IF NOT EXISTS idx_document_versions_doctype  ON document_versions(docType);
        """

    // MARK: - v4 Schema — sync_state (ADR-005 / P0.3)

    private static let v4SQL = """
        -- Single-row key/value store for SyncEngine bookmarks that must survive
        -- process restarts. First consumer is `lastServerSequence` (P0.3); later
        -- consumers may add their own keys without another migration.
        CREATE TABLE IF NOT EXISTS sync_state (
            key     TEXT    PRIMARY KEY NOT NULL,
            value   TEXT    NOT NULL
        );
        """

    // MARK: - v5 Schema — naming_counters (ADR-014 / P1.1)

    private static let v5SQL = """
        -- Per-series monotonic counters used by NamingSeriesStrategy.
        -- `seriesKey` is the DocType-scoped prefix after date-token expansion
        -- (e.g. "SalesInvoice::SINV-2026-"), so counters reset naturally when
        -- the expanded prefix rolls over (new year / month / day).
        CREATE TABLE IF NOT EXISTS naming_counters (
            seriesKey   TEXT    PRIMARY KEY NOT NULL,
            value       INTEGER NOT NULL DEFAULT 0
        );
        """

    // MARK: - v6 Schema — scheduler_state (P1.4)

    private static let v6SQL = """
        -- Last-run timestamps per scheduled task. Survives process restarts so
        -- the launch-time due-check can decide whether a task should fire
        -- immediately (cadence elapsed while the app was closed) or wait.
        --
        -- `taskKey` is the resolver-stable identity of one declaration:
        --   "<appId>::<declarationId>"
        -- which keeps it usable across reinstall (same app id, same decl id =>
        -- preserved cadence) and isolates apps from each other.
        CREATE TABLE IF NOT EXISTS scheduler_state (
            taskKey     TEXT    PRIMARY KEY NOT NULL,
            lastRunAt   TEXT    NOT NULL
        );
        """

    // MARK: - v7 Schema — tree parent (W8)

    private static let v7SQL = """
        -- W8: Tree DocType support — parent-child hierarchy within a DocType.
        -- parentId references another row in the same documents table.
        ALTER TABLE documents ADD COLUMN parentId TEXT;
        CREATE INDEX IF NOT EXISTS idx_documents_parentId ON documents(parentId);
        """

    // MARK: - v8 Schema — workflow_transitions (Phase A §3.3)

    private static let v8SQL = """
        -- Append-only history of every workflow state transition. Previously
        -- WorkflowEngine returned a WorkflowTransitionHistory record but did
        -- not persist it; this table closes that gap so financial / approval
        -- audit trails survive.
        CREATE TABLE IF NOT EXISTS workflow_transitions (
            id              TEXT    PRIMARY KEY NOT NULL,
            documentId      TEXT    NOT NULL,
            docType         TEXT    NOT NULL,
            workflowId      TEXT    NOT NULL,
            fromState       TEXT    NOT NULL,
            toState         TEXT    NOT NULL,
            action          TEXT    NOT NULL,
            userId          TEXT    NOT NULL,
            timestamp       TEXT    NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_workflow_transitions_document
            ON workflow_transitions(documentId);
        CREATE INDEX IF NOT EXISTS idx_workflow_transitions_workflow
            ON workflow_transitions(workflowId);
        """

    // MARK: - v9 Schema — naming_counter_blocks (Phase B §3.7, ADR-042)

    private static let v9SQL = """
        -- Per-device counter blocks for naming-series IDs. Each device
        -- reserves a contiguous block of N values from the shared
        -- `naming_counters` allocator, then issues counter values out of
        -- its local block without touching the shared row again until the
        -- block is exhausted. This breaks the multi-device offline collision
        -- (two devices can't both pick `SINV-2026-0001`) without depending
        -- on a server round-trip per save.
        --
        -- `seriesKey` matches the key used by `NamingSeriesStrategy`
        -- (e.g. "SalesInvoice::SINV-2026-"). `deviceId` matches
        -- `DocumentEngine.deviceId`. `nextValue` is the next value the
        -- device will issue (always within `[blockStart, blockEnd]`); when
        -- it exceeds `blockEnd`, the device claims a fresh block.
        CREATE TABLE IF NOT EXISTS naming_counter_blocks (
            seriesKey   TEXT    NOT NULL,
            deviceId    TEXT    NOT NULL,
            blockStart  INTEGER NOT NULL,
            blockEnd    INTEGER NOT NULL,
            nextValue   INTEGER NOT NULL,
            PRIMARY KEY (seriesKey, deviceId)
        );
        """

    // MARK: - v10 Schema — attachments (Phase C / P3.1, ADR-043)

    private static let v10SQL = """
        -- File attachments per document. Bytes live on disk under the
        -- attachment store's root directory; this table holds metadata only.
        -- `fieldKey` is nullable: null means "general document attachment"
        -- (not bound to a specific FieldType.attachment field), non-null
        -- binds the attachment to the named field for typed UI rendering.
        --
        -- `sha256` enables content-addressable dedup at the store layer
        -- and integrity checks at read time.
        CREATE TABLE IF NOT EXISTS attachments (
            id           TEXT    PRIMARY KEY NOT NULL,
            documentId   TEXT    NOT NULL,
            docType      TEXT    NOT NULL,
            fieldKey     TEXT,
            fileName     TEXT    NOT NULL,
            mimeType     TEXT    NOT NULL DEFAULT 'application/octet-stream',
            byteSize     INTEGER NOT NULL,
            storagePath  TEXT    NOT NULL,
            uploadedAt   TEXT    NOT NULL,
            uploadedBy   TEXT    NOT NULL,
            sha256       TEXT    NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_attachments_document ON attachments(documentId);
        CREATE INDEX IF NOT EXISTS idx_attachments_doctype  ON attachments(docType);
        CREATE INDEX IF NOT EXISTS idx_attachments_field    ON attachments(documentId, fieldKey);
        """

    // MARK: - v11 Schema — notification_log (Phase D / item 13, ADR-048)

    private static let v11SQL = """
        -- Persisted notification log. Replaces the in-memory default sink
        -- (`InMemoryNotificationLog`) for production. Channels (in-app
        -- inbox, future email/SMS adapters) read from / write to this
        -- table via `SQLiteNotificationLog` and `NotificationInbox`.
        --
        -- `readAt` is null until the in-app inbox marks the entry read.
        CREATE TABLE IF NOT EXISTS notification_log (
            id          TEXT    PRIMARY KEY NOT NULL,
            appId       TEXT    NOT NULL,
            docType     TEXT    NOT NULL,
            documentId  TEXT    NOT NULL,
            channel     TEXT    NOT NULL,
            recipient   TEXT,
            subject     TEXT    NOT NULL DEFAULT '',
            body        TEXT    NOT NULL DEFAULT '',
            emittedAt   TEXT    NOT NULL,
            readAt      TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_notification_recipient
            ON notification_log(recipient);
        CREATE INDEX IF NOT EXISTS idx_notification_emittedAt
            ON notification_log(emittedAt);
        CREATE INDEX IF NOT EXISTS idx_notification_unread
            ON notification_log(recipient, readAt);
        """

    // MARK: - v12 Schema (Custom Fields)

    private static let v12SQL = """
        -- End-user customizations layered on top of a base DocType. (ADR-021)
        --
        -- A row here adds a single field to `docType` without mutating the
        -- base DocType definition, so app-manifest reinstalls don't clobber
        -- it and the field can be removed without a schema migration.
        --
        -- `insertAfter` is the field key the custom field should be placed
        -- after in the rendered form; NULL means "append to the end".
        -- `field_definition` is the JSON-encoded FieldDefinition.
        CREATE TABLE IF NOT EXISTS custom_fields (
            id                TEXT PRIMARY KEY NOT NULL,
            doctype           TEXT NOT NULL,
            field_key         TEXT NOT NULL,
            insert_after      TEXT,
            field_definition  TEXT NOT NULL,
            created_at        TEXT NOT NULL,
            updated_at        TEXT NOT NULL,
            UNIQUE (doctype, field_key)
        );

        CREATE INDEX IF NOT EXISTS idx_custom_fields_doctype
            ON custom_fields(doctype);
        """

    // MARK: - v13 Schema — posting_batches (Phase 1 / atomic posting)

    private static let v13SQL = """
        -- One row per posting attempt for a submittable source document. The
        -- batch is written in the SAME transaction as the source document's
        -- submit (via UnitOfWork), so a submitted financial / stock document can
        -- never silently end up unposted, partially posted, or unbalanced: either
        -- the batch row (status='posted') and its ledger rows commit together, or
        -- the whole submit rolls back.
        --
        -- `id` is deterministic (`POST-<sourceId>-v<version>`) so a retry is
        -- idempotent. `status`: pending | posted | failed | reversed.
        -- `reversalOfBatch` links a reversal batch to the batch it reverses.
        CREATE TABLE IF NOT EXISTS posting_batches (
            id              TEXT    PRIMARY KEY NOT NULL,
            sourceType      TEXT    NOT NULL,
            sourceId        TEXT    NOT NULL,
            status          TEXT    NOT NULL DEFAULT 'pending',
            version         INTEGER NOT NULL DEFAULT 1,
            errorCode       TEXT,
            errorMessage    TEXT,
            postedAt        TEXT,
            postedBy        TEXT    NOT NULL DEFAULT '',
            reversalOfBatch TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_posting_batches_source
            ON posting_batches(sourceType, sourceId);
        CREATE INDEX IF NOT EXISTS idx_posting_batches_status
            ON posting_batches(status);
        """
}
