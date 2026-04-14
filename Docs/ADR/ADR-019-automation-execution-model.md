# ADR-019 — Automation Execution Model

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe executes automation through multiple mechanisms: Server Scripts (sandboxed Python running on the server), Webhooks (HTTP callbacks), background RQ jobs, and Notification rules. All require a server process. Mercantis has no server (ADR-010) and cannot execute arbitrary code (ADR-008).

An automation capability is still needed: setting field values on save, sending notifications, validating conditions, and assigning documents — all triggered declaratively by document events.

## Decision

Mercantis Core executes automation rules on-device, synchronously during the document lifecycle. When a document event fires (e.g. `on_save`, `on_submit`), the `DocumentEngine` evaluates all matching `AutomationRule` entries from installed app manifests.

Each `AutomationRule` has:
- A `conditionExpression` evaluated by `ExpressionEngine` against the document context.
- An `actions` array, executed in declared order.

**AutomationActionRegistry:** Action dispatch uses a registry pattern rather than a string-switch. Each built-in action type is a conformance of the `AutomationActionHandler` protocol:

```swift
protocol AutomationActionHandler {
    static var actionType: String { get }
    func execute(document: inout Document, parameters: [String: String], context: AutomationContext) throws
}
```

Built-in action types registered at startup:

- `set_value` — Set a field on the document.
- `set_status` — Change the workflow state.
- `send_notification` — Create a `NotificationLog` entry.
- `validate` — Throw a validation error if a condition fails (blocking save).
- `assign` — Assign the document to a user or role.

`AutomationActionRegistry` maps `actionType` strings to handler instances. New action types are added by registering a conformance compiled into Core — not by downloading code.

Actions execute within the same database transaction as the document save. If any action throws an error, the entire save rolls back. Long-running or external actions (e.g. actual email delivery) are deferred to the `SchedulerService` for post-commit execution.

## Consequences

**Positive:**
- Automations work fully offline.
- Deterministic execution order — actions run in the declared sequence.
- Transactional consistency — a failing action rolls back the whole save, preventing partial state.
- Registry-based dispatch is type-safe and independently testable per handler.
- Auditable — every automation execution is logged to `audit_log`.

**Negative:**
- No async automations during save — complex rule chains may cause a perceptible pause in the UI.
- Cannot call external APIs synchronously (no network I/O in the save transaction).
- Limited to built-in action types — arbitrary logic requires a Core update.

**Neutral:**
- The deferred action queue (via `SchedulerService`) handles post-commit side effects such as sending emails when connectivity returns.

---

*See also: [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md), [ADR-010 — Pure Client-Side Architecture](ADR-010-pure-client-side-architecture.md), [ADR-015 — Declarative Extension Points for App Extension](ADR-015-declarative-hooks-app-extension.md), [ADR-025 — Automation Action Registry](ADR-025-automation-action-registry.md)*
