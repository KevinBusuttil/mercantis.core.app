# ADR-012 — EventBus for Internal Pub/Sub

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe uses a `doc_events` hook system where apps register Python functions to be called on document lifecycle events. This is tightly coupled to its server-side hook resolution and Python's dynamic import system. Mercantis needs a decoupled internal communication mechanism that works within a single-process Swift application.

Without a decoupling layer, subsystems such as DocumentEngine, WorkflowEngine, and SyncEngine would hold direct references to each other, creating a tightly coupled dependency graph that is hard to test and extend.

## Decision

Mercantis Core uses an in-process `EventBus` (observer pattern) for internal communication between subsystems. Events are string-named (e.g. `document.saved`, `workflow.transition`). Subscribers register closures. The EventBus is synchronous within the calling context — it does not perform cross-thread dispatch by default.

## Consequences

**Positive:**
- Fully decoupled subsystems: DocumentEngine does not import WorkflowEngine or SyncEngine.
- Easy to test: subscribe a closure in a test, assert it fires with the expected payload.
- No dependency on external infrastructure (no message broker, no notification framework).
- Lightweight implementation with negligible overhead.

**Negative:**
- Synchronous by default: a slow subscriber blocks the caller.
- No persistence of events — fire-and-forget; missed events are lost.
- No guaranteed delivery or ordering guarantees across subscribers.
- Memory leaks if subscriptions are not cancelled when subscribers are deallocated.

**Neutral:**
- Apps wire into the EventBus via declarative hooks in their manifest. The `AppRuntime` resolves manifest hook declarations into EventBus subscriptions at install time.

---

*See also: [ADR-004 — Declarative App / Plugin Model](ADR-004-declarative-app-plugin-model.md), [ADR-015 — Declarative Hooks for App Extension](ADR-015-declarative-hooks-app-extension.md)*
