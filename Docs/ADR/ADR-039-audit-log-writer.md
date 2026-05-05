# ADR-039 — `audit_log` Writer / Reader

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

Migration v1 created the `audit_log` table on day one with the documented
intent of recording every document mutation. In practice, **nothing ever
wrote to it**. §4.3 of `ARCHITECTURE.md` referred to it as the immutable
audit trail; STATUS.md §3.2 flagged it as "Missing-in-fact" — created,
never used. The sync queue was acting as a de-facto log, but ADR-028's
pruning policy makes that an unreliable substitute for compliance.

## Decision

1. Introduce `AuditLogWriter` with:
   - `append(_:in:)` — writes inside an existing GRDB transaction.
   - `append(documentId:docType:userId:action:before:after:in:)` — convenience
     overload that JSON-encodes a `{before, after}` payload.
   - `entries(forDocumentId:)` — full chronological history per document.
   - `entries(forDocType:limit:offset:)` — newest-first, paged history.
2. `DocumentEngine` constructs an `AuditLogWriter` at init (no public
   surface added — the writer is internal plumbing) and invokes it inside
   the same `database.write { db in … }` block that runs the document
   upsert and mutation-log append. The audit row commits **atomically**
   with the document row, so a partially applied write cannot leave the
   audit trail out of sync.
3. Wired into every write path: `save` (action `create` or `update`),
   `applyRemote` (`applyRemote`), `delete` (`delete`), `submit`
   (`submit`), `cancel` (`cancel`), `amend` (`amend`).
4. Lifecycle entries (`submit`/`cancel`/`amend`) are written as a follow-on
   row to the underlying save, so the trail records both the field change
   and the lifecycle event explicitly.
5. `DocumentEngine.auditEntries(...)` exposes the reader API for Hub.

The audit log is **not** subject to ADR-028's sync-queue pruning. Compliance
retention rules belong to a future, separate policy.

## Consequences

**Positive**

- Compliance-grade trail: every mutation writes one or two rows in an
  append-only table that survives sync queue pruning.
- Atomicity: the audit append happens in the same write block as the
  document mutation, so consumers never observe a state where the row
  exists without an audit entry (or vice versa).
- The reader API supports both the "history of one document" and "what
  happened to this DocType today" views without callers having to write
  SQL.

**Negative**

- Storage: every write doubles to disk (mutation row + audit row). Audit
  entries are small JSON blobs, so impact is bounded but not zero.
- Lifecycle audit rows commit in a separate transaction from the save
  they describe. The save's atomicity is preserved; in the unlikely event
  the lifecycle append fails after a successful save, the document is
  durable but the lifecycle row is missing — caller sees the throw and
  can compensate.

**Neutral**

- The audit-log payload format is `{ "before": {...}|null, "after": {...}|null }`
  with `FieldValue` JSON inside each map. Sufficient for diffs; not yet
  index-friendly. A future migration could extract `before`/`after` keys
  into derived columns if the read pattern demands it.
