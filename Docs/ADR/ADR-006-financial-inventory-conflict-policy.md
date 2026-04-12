# ADR-006 — Financial & Inventory Conflict Policy

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

In an offline-first system, two users on different devices may edit the same document concurrently while both are offline. When their devices reconnect, the sync engine must decide what to do with the conflicting mutations.

A single conflict resolution strategy does not suit all data types:

- A **customer's display name** can safely use last-write-wins — a brief window of inconsistency is acceptable.
- A **stock quantity** or **invoice amount** cannot safely use last-write-wins — silently discarding one user's edit could result in incorrect inventory counts or financial records.
- A **ledger entry** or **audit log record** should never be modified or discarded once created.

## Decision

Conflict resolution is **per-DocType**, configured via `SyncPolicy.conflictResolution`. Three policies are defined:

### Policy 1 — Last-Write-Wins (LWW)

> Used for: descriptive, non-financial fields (e.g. display names, addresses, settings).

The mutation with the higher server sequence number wins. The losing mutation is recorded in the audit log. No user intervention required.

### Policy 2 — Version-Checked Merge (VCM)

> Used for: financial and inventory documents (e.g. invoices, stock entries, payment records).

Both mutations carry the `syncVersion` of the document they were based on. If two mutations have the same base `syncVersion`, they are concurrent edits and constitute a conflict. The document is marked `conflicted` and presented to the user for manual resolution. The user chooses a version; a `resolveConflict` mutation is recorded.

`SyncPolicy.immutableAfterSubmit = true` can be used for documents that should not be editable after they reach a submitted/posted state, further reducing the conflict surface.

### Policy 3 — Append-Only (AO)

> Used for: immutable-once-created records (e.g. ledger entries, audit log, payment receipts).

These records are always accepted as new rows. There is no concept of conflict because they are never updated or deleted.

## Consequences

**Positive:**
- Financial and inventory data is protected from silent data loss.
- Simple descriptive data does not burden users with unnecessary conflict resolution.
- The policy is co-located with the DocType definition, making it explicit and reviewable.
- Append-only records provide a tamper-evident audit trail.

**Negative:**
- VCM requires a conflict resolution UI, which adds complexity to the UI Shell.
- Apps must carefully classify each DocType's conflict resolution policy; a mis-classification could lead to data integrity issues.

**Neutral:**
- `ConflictResolver` in the Sync Engine implements all three policies and is unit-testable independently.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md)*
