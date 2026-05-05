# ADR-041 — Scheduled Automation Rules

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`AutomationRule` carries a `triggerEvent` field with values like `onSave`,
`onSubmit`, `onCancel`, and — per the existing ADR-019 contract —
`onSchedule`. The runner subscribed to document lifecycle events but had
no path for `onSchedule`: rules with that trigger parsed and registered
into the runner, but never fired. STATUS.md §3.8 flagged this.

A separate (orthogonal) feature already exists:
`AppManifest.extensionPoints.schedulerEvents` declarations are bound by
`ExtensionPointResolver` to `SchedulerService` and dispatched through
`ExtensionActionDispatcher`. That covers "fire these actions on a
cadence" but not "for each document of this DocType, evaluate this
condition and run these actions" — which is what
`AutomationRule(triggerEvent: "onSchedule")` is meant to express.

## Decision

Three pieces:

1. **Cadence on the rule.** `AutomationRule` gains an optional
   `schedule: ScheduleInterval?` field. Required when
   `triggerEvent == "onSchedule"`; ignored otherwise. Backward-compat
   decode: existing manifests without the field round-trip cleanly.

2. **Runner ↔ scheduler binding.** `AutomationRunner` accepts an
   optional `scheduler: ExtensionSchedulerRegistrar?` at init. When
   present:
   - `register(rules:appId:)` registers a `ScheduledTask` per
     scheduled rule with declaration id `"automation::<ruleId>"`.
   - `unregister(appId:)` cancels every scheduled handle for that
     app.
   - `applyManifests(_:)` re-binds across all manifests atomically
     (cancel old, register new).

3. **Tick semantics.** When the scheduler fires the rule's task, the
   runner iterates every document of `rule.docType` (via the
   `AutomationDocumentGateway.listDocuments(docType:)` method,
   added in this ADR), evaluates `rule.conditionExpression` per
   document, and runs the actions on matches. Errors per-document
   are reported and the iteration continues — one bad document
   does not abort the rest.

When the runner has no gateway, scheduled rules still fire, but
against a placeholder document. This preserves the
`send_notification` / `assign` use cases that don't need fields.

## Consequences

**Positive**

- `onSchedule` rules now actually fire — the third leg of ADR-019's
  trigger contract is real.
- The `ScheduleInterval` type is reused (`.hourly`, `.daily`,
  `.cron(...)`, etc.), so manifests don't grow a new schedule grammar.
- Per-document iteration matches ERPNext semantics ("once a day,
  recompute outstanding for every Sales Invoice").
- Existing `extensionPoints.schedulerEvents` path is untouched —
  scheduled rules and scheduler events are separate concerns
  routed through the same `SchedulerService`.

**Negative**

- The runner now reads through `gateway.listDocuments(docType:)` on
  every tick of every rule — for large tables and many rules, this
  is O(rules × documents). Acceptable today; a future optimisation
  could push the rule's condition into `DocumentEngine.list(...)`'s
  `whereExpression` (Phase A §3.1 already supports this).
- `gateway.listDocuments(docType:)` runs with `applyRowAccess: false`
  because automation runs as a system actor, not as a specific user.
  The trade-off is documented; security-sensitive automation should
  add an explicit row predicate via `conditionExpression`.

**Neutral**

- The existing trigger matcher in `AutomationRunner.handle` already
  matches `"onSchedule" == "onschedule"` case-insensitively, so no
  changes needed there.
- Manifest authors who previously used
  `extensionPoints.schedulerEvents` for cron actions can keep doing
  so. The new path is the ergonomic choice when the action is
  scoped to documents of a specific DocType; the extension-point
  path is the right tool for document-less cadenced work.
