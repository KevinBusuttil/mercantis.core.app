# ADR-028 — Sync Queue Pruning Strategy

**Status:** Accepted
**Date:** 2026-04-23

---

## Context

Every persistent write in Core produces exactly one `MutationRecord` in `sync_queue` (ADR-005). Rows progress through a small status machine:

- `.pending` — local write waiting to be pushed.
- `.pushed` — local write acknowledged by the cloud adapter.
- `.applied` — remote write that has been applied locally.
- `.conflicted` — remote write that could not be applied because of a version/policy mismatch (ADR-006).

`.pushed` and `.applied` rows accumulate indefinitely. A device that has been running for months accumulates a queue proportional to its entire write history — even though those rows no longer influence any read path:

- Once the server has acknowledged a `.pushed` row, the authoritative record lives in the server's log, not ours.
- `.applied` rows are pure local idempotency / audit memoization: `SyncEngine.storeMutationAsApplied` uses `INSERT OR REPLACE` and nothing else in Core depends on these rows being retrievable later. Re-pulling from the adapter would not reproduce them since `lastServerSequence` (ADR-005 / P0.3) is already advanced past them.

`.pending` rows are load-bearing — they are the next push payload — and `.conflicted` rows are user-facing: both must be retained indefinitely regardless of age.

There is no existing policy deciding when acknowledged rows are safe to delete, and unbounded queue growth is the last open P0 correctness/trust item against the mutation log.

## Decision

Acknowledged rows (`.pushed` and `.applied`) are deleted from `sync_queue` by `SyncEngine.pruneSyncQueue(force:)` according to a `SyncQueuePruneConfig`:

```swift
public struct SyncQueuePruneConfig: Sendable {
    public var pushedRetention: TimeInterval   // default: 30 days
    public var appliedRetention: TimeInterval  // default: 30 days
    public var pruneInterval: TimeInterval     // default: 24 hours
    public static let `default`: SyncQueuePruneConfig
}
```

**Eligibility**

- `.pushed` rows are eligible once `localTimestamp < now - pushedRetention`.
- `.applied` rows are eligible once `localTimestamp < now - appliedRetention`.
- `.pending` and `.conflicted` rows are never deleted by this method.

**Throttling**

`pruneSyncQueue(force: false)` is a no-op if a prune ran more recently than `pruneInterval`. The last prune timestamp is persisted in the `sync_state` key/value table (introduced in v4 for ADR-005 / P0.3) under the key `"syncQueuePrunedAt"`. `force: true` bypasses the throttle.

**Scheduling**

No new timers. `SyncEngine.pushPendingMutations()` and `SyncEngine.pullAndApplyRemoteMutations()` each call `pruneSyncQueue(force: false)` at the end of a successful run. Under the default 24-hour throttle this yields at most one prune per day per device while sync activity continues, at the natural moments when the DB write lock is already in use for sync work.

**Transactional behaviour**

Both DELETE statements and the watermark UPSERT run inside a single `database.write { db in … }` block. Either the rows are gone and the watermark is advanced, or nothing changed.

**No `VACUUM`**

The method does not call SQLite `VACUUM`. SQLite reuses freelist pages automatically, and `VACUUM` requires an exclusive database lock that would stall concurrent sync and UI reads. The phrase "vacuum budgeting" in this ADR refers to throttling the prune itself — not issuing `VACUUM` commands.

**No schema change**

The v4 `sync_state` key/value table is reused. No migration is required.

## Consequences

**Positive:**

- Bounded queue growth at steady state: the acknowledged-row footprint is proportional to the retention window, not to lifetime device history.
- `pending` and `conflicted` rows are preserved, so no in-flight work or unresolved conflict is ever lost to pruning.
- No extra timer, actor, or scheduler needed. Pruning piggybacks on existing sync calls.
- Configurable per deployment: a long-lived audit-sensitive deployment can set `appliedRetention = .infinity`-equivalent (a very large value) without code changes.

**Negative:**

- An operator-driven audit that wants the complete historical mutation stream cannot rely on `sync_queue` as the source — `document_versions` (ADR-024) is the durable field-level history, and the cloud adapter holds the server-side mutation log.
- `.applied` rows no longer provide a local cross-check against the adapter's history after the retention window. In practice this duplicates server state and is not consulted by any Core read path.

**Neutral:**

- The throttle is expressed as "at most one prune per `pruneInterval`", not "guaranteed once per `pruneInterval`". On a device that stops syncing, the queue will not prune further until sync resumes. This is intentional: idle devices have no write pressure to justify waking the DB.
- `pruneSyncQueue(force: true)` is a public method. Callers (tests, explicit maintenance flows) may run it on demand.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md), [ADR-006 — Financial & Inventory Conflict Policy](ADR-006-financial-inventory-conflict-policy.md), [ADR-024 — Document Versioning and Field-Level Diff Tracking](ADR-024-document-versioning-diff-tracking.md)*
