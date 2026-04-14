# ADR-009 — Single Documents Table with JSON Payload

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe creates a dedicated SQL table per DocType (e.g. `tabSales Invoice`) with one column per field. This enables native SQL queries, joins, and indexes on any field. However, it requires DDL migrations whenever a field is added or changed, which is complex in an offline-first, multi-device sync environment where schema changes must propagate across devices.

Coordinating DDL migrations across multiple offline devices — each potentially at a different schema version — introduces significant risk of data corruption and makes conflict resolution much harder.

## Decision

Mercantis Core stores all documents in a single `documents` table with a JSON `payload` column. Queryable fields are extracted into indexed columns via `IndexDefinition` in the DocType metadata. When a field is declared as an `IndexDefinition`, the Storage layer extracts its value from the payload and writes it to a dedicated indexed column at save time.

## Consequences

**Positive:**
- No DDL migrations when fields change. Schema evolution is a metadata update only.
- Sync is simpler — no table-per-DocType DDL to propagate across devices.
- Offline-first is natural: any device can accept any document regardless of local schema version.
- Adding a new DocType requires no database change.

**Negative:**
- Queries on non-indexed fields require JSON extraction (slower than native column queries).
- No native SQL joins between DocType fields without explicit index promotion.
- Payload size can grow for documents with many fields.

**Neutral:**
- Performance is acceptable for the scale of on-device data. If a hot field needs better query performance, adding an `IndexDefinition` promotes it to a real indexed column without a full migration.

---

*See also: [ADR-002 — SQLite as Local Source of Truth](ADR-002-sqlite-local-source-of-truth.md), [ADR-013 — Submit / Cancel / Amend Document Lifecycle](ADR-013-submit-cancel-amend-lifecycle.md)*
