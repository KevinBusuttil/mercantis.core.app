# ADR-048 — Persistent Notification Log + In-App Inbox

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`SendNotificationHandler` (P1.2) writes through `NotificationLogWriter`,
but the only built-in writer was `InMemoryNotificationLog` — entries
disappeared on process exit. STATUS.md §4 listed `NotificationLog` +
"at least one channel" as the Phase D notification gap; the in-app
inbox is the natural first channel because it doesn't require external
account credentials.

## Decision

Migration v11 adds the `notification_log` table:

```
notification_log(id PK, appId, docType, documentId, channel,
                 recipient, subject, body, emittedAt, readAt)
```

Three new public types under `mercantis core/Notifications/`:

1. **`SQLiteNotificationLog`** — `NotificationLogWriter` that persists
   each entry into `notification_log`. INSERT-OR-NOTHING on `id`
   collision keeps writes idempotent under retry.
2. **`CompositeNotificationLog`** — fans out one entry to multiple
   downstream sinks. Lets a host pair persistence with extra channels
   (console, future email/SMS adapters) without the handler protocol
   knowing about them.
3. **`ChannelFilteredNotificationLog`** — wraps a downstream sink and
   only forwards entries whose `channel` matches one of the configured
   ids. The seam future-proofs per-channel adapters.

Reader-side: **`NotificationInbox`** queries the persisted table:

- `entries(forRecipient:unreadOnly:limit:offset:)` — paged feed.
- `unreadCount(forRecipient:)`.
- `markRead(id:)` / `markAllRead(forRecipient:)` — sets `readAt`.
- `delete(id:)` — hard-delete an inbox row.

`recipient = NULL` is its own feed (broadcast / system messages), kept
distinct from any specific user's queue.

## Consequences

**Positive**

- Notifications survive process restarts and app re-installs (the
  table is not pruned with the sync queue per ADR-028).
- The in-app inbox is a real, queryable surface that
  `MercantisCoreUI` (or Hub's own SwiftUI) can render directly via
  `NotificationInbox`.
- Adding email / push / SMS later is a single new
  `NotificationLogWriter` conformance plus a `CompositeNotificationLog`
  composition; the handler protocol does not change.

**Negative**

- The composite writer is fire-and-forget — one sink throwing /
  failing does not stop the others, but the composite itself does
  not surface per-sink errors. Acceptable: the default sink (the
  SQLite log) is the source of truth; downstream channels are
  side effects.
- The schema does not include a typed-payload column. Subjects /
  bodies remain free-form strings with `{field}` substitution from
  `SendNotificationHandler`. A structured-payload column can be
  added in a future migration if rich notifications (deeplinks,
  thumbnails) become a requirement.

**Neutral**

- `InMemoryNotificationLog` ships unchanged. Tests and headless
  scripts keep using it; production wiring composes
  `SQLiteNotificationLog` (and future channel adapters) via
  `CompositeNotificationLog`.
- Audit-log integration is left to the caller. The
  `SendNotificationHandler` itself does not write to `audit_log` —
  the notification *is* the audit trail. If a host needs both, it
  can compose a sink that also writes to the audit log.
