# ADR-005 — Sync via Mutation Log

**Status:** Accepted  
**Date:** 2026-04-12

---

## Context

Mercantis Core is offline-first. Devices must be able to create, update, and delete documents with no network connectivity, then synchronise those changes to a cloud backend when connectivity is restored. The sync mechanism must:

- Be reliable: no change is ever silently lost.
- Be auditable: every change is attributable to a device, user, and timestamp.
- Support conflict detection: concurrent edits from different devices must be detectable.
- Avoid requiring a continuous connection: a device may be offline for days.
- Be composable: the same mechanism that syncs documents also syncs schema changes and app installations.

## Decision

**Every persistent write in Mercantis Core atomically appends an immutable `MutationRecord` to the `sync_queue` table.** This is the mutation log.

A `MutationRecord` carries:
- `id` (UUID) — globally unique identifier.
- `type` — the mutation type (`upsertDocument`, `deleteDocument`, `patchChildRows`, `updateSchema`, `installApp`, `resolveConflict`, etc.).
- `payload` (JSON) — the full content of the mutation.
- `deviceId` — the originating device.
- `userId` — the user who initiated the action.
- `localTimestamp` — the device clock at the time of the write.
- `syncVersion` — a monotonically increasing integer per document, used for conflict detection.
- `status` — lifecycle state: `pending` → `pushed` → `applied`.

The `SyncEngine` implements the push/receive/apply/acknowledge flow:
1. **Push** — Read `pending` mutations, send to cloud adapter, mark as `pushed`.
2. **Receive** — Poll cloud adapter for mutations from other devices.
3. **Apply** — For each remote mutation, resolve conflicts using the DocType's `SyncPolicy`, apply to the local database.
4. **Acknowledge** — Mark applied mutations as `applied`.

**Direct SQLite writes that bypass the Document Engine are prohibited.** Any write that does not produce a `MutationRecord` is invisible to the sync engine and will be overwritten on next sync.

## Consequences

**Positive:**
- Complete, auditable history of every change on every device.
- Sync is eventually consistent and tolerates arbitrary offline periods.
- Schema changes and app installations are propagated through the same mechanism as document changes.
- The mutation log doubles as an audit trail.
- Conflict detection is straightforward: compare `syncVersion` values.

**Negative:**
- The `sync_queue` table grows indefinitely and must be periodically pruned after mutations are acknowledged.
- Every write has slightly higher overhead (two inserts: document + mutation record).
- Discipline required: all code must write through `DocumentEngine`, never directly to SQLite.

**Neutral:**
- The cloud adapter is a separate protocol; Core defines the interface, implementations are separate.

---

*See also: [ADR-002 — SQLite as Local Source of Truth](ADR-002-sqlite-local-source-of-truth.md), [ADR-006 — Financial & Inventory Conflict Policy](ADR-006-financial-inventory-conflict-policy.md)*
