# ADR-002 — SQLite as Local Source of Truth

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Mercantis Core must operate fully offline. Users in the field — warehouses, remote offices, areas with poor connectivity — must be able to create, read, update, and delete documents without any network access. Changes must be durable across app restarts.

Several local persistence options were considered:

- **Core Data** — Mature Apple framework, but complex concurrency model, difficult cross-platform migration, and impedance mismatch with JSON-defined dynamic schemas.
- **Realm** — Third-party, has its own sync server; conflicts with our custom sync design.
- **SQLite (raw)** — Reliable and portable, but verbose Swift API.
- **SQLite via GRDB** — Type-safe Swift API, powerful query builder, `DatabasePool` for concurrent reads/writes, built-in migration support.
- **In-memory / file-based property lists** — Not suitable for relational queries or large document sets.

## Decision

All persistent state in Mercantis Core MUST be stored in a **SQLite database managed via [GRDB](https://github.com/groue/GRDB.swift)**. The database is the single local source of truth.

Specific schema choices:
- Documents are stored with **system columns** for indexed access (`id`, `doctype`, `company`, `status`, `createdAt`, `updatedAt`, `syncVersion`, `syncState`) and a **JSON `payload` column** for the user-defined field values.
- Field values that are declared as indexed in `IndexDefinition` are extracted into dedicated columns at write time.
- Child table rows are stored in a separate `document_children` table linked by `parentId`.
- The mutation log (`sync_queue`) is a plain table of `MutationRecord` rows.

Direct writes to SQLite that bypass `DocumentEngine` are **prohibited** — all writes must go through the Document Engine to ensure the mutation log is maintained correctly.

## Consequences

**Positive:**
- Full offline capability with ACID transactions.
- Efficient relational queries for lists, filters, and reports.
- GRDB provides type-safe access patterns and `DatabasePool` for safe concurrent access.
- SQLite is well-understood, widely tested, and has no license cost.

**Negative:**
- Schema migrations must be managed carefully; `MigrationRunner` tracks versions and runs forward-only migrations.
- Dynamic JSON payload means some queries are less efficient than fully normalised schemas (mitigated by extracted index columns).

**Neutral:**
- The GRDB package must be added as a dependency via Swift Package Manager or Xcode's package integration.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md)*
