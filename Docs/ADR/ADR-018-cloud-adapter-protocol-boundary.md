# ADR-018 — Cloud Adapter as Protocol Boundary

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe is tightly coupled to its infrastructure stack (MariaDB, Redis, Gunicorn, Nginx). Mercantis Core is infrastructure-agnostic — it must work with any cloud backend (Firebase, Supabase, custom REST API, or no backend at all). Different customers and deployments will use different cloud services; Core must not hard-code any of them.

## Decision

Mercantis Core defines a `CloudAdapter` Swift protocol with the following interface:

```swift
public protocol CloudAdapter: Sendable {
    func pushMutations(_ mutations: [MutationRecord]) async throws -> [SyncAcknowledgement]
    func pullMutations(since version: SyncVersion) async throws -> [RemoteMutation]
}
```

Conflict resolution is currently handled inside Core by `SyncEngine` and `ConflictResolver`; `CloudAdapter` is responsible only for transport of mutations and acknowledgements.

Core never imports or references any specific cloud SDK. The host application provides a concrete `CloudAdapter` implementation and injects it into the `SyncEngine` at initialisation. Core ships with a `NoOpCloudAdapter` for fully offline use.

## Consequences

**Positive:**
- Core is cloud-agnostic — the same binary works with any backend.
- Backends can be swapped or upgraded without touching Core.
- Testable with mock adapters in unit tests.
- Works fully offline with `NoOpCloudAdapter` — no network required.

**Negative:**
- The protocol boundary adds indirection.
- Complex cloud features (real-time subscriptions, server-side validation, or server-mediated conflict workflows) must either be modeled as higher-level host-app concerns or added through future protocol evolution.
- The host app bears responsibility for providing a correct, secure adapter implementation.

**Neutral:**
- A future production `CloudAdapter` may target a Frappe-compatible REST API, enabling Mercantis Hub to sync with Frappe/ERPNext backends.

---

*See also: [ADR-005 — Sync via Mutation Log](ADR-005-sync-via-mutation-log.md), [ADR-010 — Pure Client-Side Architecture](ADR-010-pure-client-side-architecture.md)*
