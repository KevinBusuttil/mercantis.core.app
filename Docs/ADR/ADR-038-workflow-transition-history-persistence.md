# ADR-038 — Workflow Transition History Persistence

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`WorkflowEngine.transition(...)` returned a `WorkflowTransitionHistory`
record but did not persist it. §4.5 of `ARCHITECTURE.md` read as if the
record was written automatically. Callers who forgot to store the returned
value silently lost their workflow audit trail — a hard requirement for any
ERP that ships approvals (financial transactions, leave requests, manual
journal entries).

## Decision

1. Add migration **v8** creating a `workflow_transitions` table
   (`id`, `documentId`, `docType`, `workflowId`, `fromState`, `toState`,
   `action`, `userId`, `timestamp`).
2. Introduce `WorkflowTransitionHistoryWriter` with a write API
   (`append(_:)` / `append(_:in:)`) and a read API
   (`transitions(of:)` / `transitions(forWorkflow:limit:offset:)`).
3. `WorkflowEngine` accepts an optional writer at init. When present,
   `transition(...)` calls `writer.append(history)` immediately after
   updating `document.status`. The returned record is unchanged for callers
   that want immediate access.
4. Convenience init `WorkflowEngine(database:)` that builds the writer.
5. `DocumentEngine` exposes `workflowTransitions(of:)` /
   `workflowTransitions(forWorkflow:limit:offset:)` as a single canonical
   reader surface that Hub can call without instantiating the writer.

## Consequences

**Positive**

- The audit trail is durable by default. ERP modules built on the engine
  inherit compliance behaviour without bookkeeping.
- The reader API supports both per-document detail views and per-workflow
  reports.

**Negative**

- One extra row per transition. Negligible relative to document churn.
- The writer commits in its own short transaction (not the one that
  updated `Document.status`). In the unlikely event the writer fails after
  status updates succeed, the engine throws but the document already
  reflects the new state. Acceptable: callers see the throw and can either
  retry or escalate. A fully atomic write would couple `WorkflowEngine` to
  `DocumentEngine`'s storage; out of scope here.

**Neutral**

- Existing `WorkflowEngine()` (no writer) callers behave exactly as before,
  preserving backward compatibility.
