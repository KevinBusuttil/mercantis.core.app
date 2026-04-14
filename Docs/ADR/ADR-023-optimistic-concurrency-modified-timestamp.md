# ADR-023 — Optimistic Concurrency via Modified Timestamp

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Mercantis Core is a multi-window, potentially multi-task iOS/macOS application. Two different parts of the app (or two different async tasks in the same process) could load the same document, modify it independently, and attempt to save. Without a concurrency guard, the second save silently overwrites the first — a lost update.

This is a same-device, same-process concurrency problem. It is distinct from cross-device sync conflicts, which are handled by `ConflictResolver` and `SyncPolicy` (ADR-006).

## Decision

Documents carry a `modifiedAt: Date` timestamp. On every successful save, `DocumentEngine` updates `modifiedAt` to the current time.

On `save(_:)`, `DocumentEngine` performs an optimistic concurrency check:

1. Read the current `modifiedAt` from the database for the document being saved.
2. Compare it against the `modifiedAt` on the in-memory `Document` object.
3. If they differ (another save occurred between load and save), abort with a `ConcurrencyConflictError`.

The caller receives a structured error that includes the document ID and a suggestion to reload. The UI can prompt the user to review the latest version before re-attempting the save.

**This is separate from cross-device sync conflicts.** `ConflictResolver` handles mutations arriving from the sync layer (ADR-006). `ConcurrencyConflictError` is a local, same-device guard.

## Consequences

**Positive:**
- Prevents lost updates from concurrent in-process edits.
- No additional database columns required — `modifiedAt` is already part of the document record.
- Deterministic: the first save wins; the second is rejected with a clear error.
- Zero overhead on reads — the check is a single timestamp comparison at save time.

**Negative:**
- In highly concurrent save scenarios (e.g. automation rules triggering saves in rapid succession), callers must handle `ConcurrencyConflictError` and retry.
- Does not protect against concurrent saves from two separate OS processes sharing the same SQLite database (not a supported configuration).

**Neutral:**
- `modifiedAt` comparison uses wall clock time. On the same device, clock resolution is sufficient. Cross-device `modifiedAt` comparison is not used for this purpose (ADR-006 handles that).

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md), [ADR-006 — Financial & Inventory Conflict Policy](ADR-006-financial-inventory-conflict-policy.md)*
