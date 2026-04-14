# ADR-025 — Automation Action Registry

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

ADR-019 describes the automation execution model: `AutomationRule` entries declare action types as strings (e.g. `set_value`, `send_notification`). The original design implied a string-switch dispatch inside the automation executor.

String-switch dispatch has the same problems as stringly-typed events: silent failures for unknown action types, no compile-time verification, no isolation for testing individual action handlers.

## Decision

Mercantis Core replaces string-switch dispatch with an **`AutomationActionRegistry`**. Each action type is a conformance of `AutomationActionHandler`:

```swift
protocol AutomationActionHandler {
    static var actionType: String { get }
    func execute(document: inout Document, parameters: [String: String], context: AutomationContext) throws
}
```

`AutomationActionRegistry` maps `actionType` strings to registered handler instances. Built-in handlers are registered at Core startup:

| `actionType` | Handler | Effect |
|---|---|---|
| `set_value` | `SetValueHandler` | Sets a field on the document to the specified value. |
| `set_status` | `SetStatusHandler` | Changes the document's workflow state. |
| `send_notification` | `SendNotificationHandler` | Creates a `NotificationLog` entry. |
| `validate` | `ValidateHandler` | Evaluates a condition; throws if false (blocks save). |
| `assign` | `AssignHandler` | Assigns the document to a user or role. |

When the automation executor encounters an action, it looks up the handler in the registry by `actionType`. If no handler is registered for the given type, the action fails with a descriptive error (not a silent no-op).

New action types are added by registering a new `AutomationActionHandler` conformance compiled into Core. Downloaded apps cannot register new action types (ADR-008).

## Consequences

**Positive:**
- Each handler is independently testable.
- Unknown action types fail explicitly — no silent no-ops.
- New action types are extensible via protocol conformance.
- Registry is inspectable — the set of registered action types is discoverable at runtime.

**Negative:**
- New action types require a Core update (same constraint as before, now made explicit).
- Registry must be initialised before any automation executes; startup order matters.

**Neutral:**
- The registry pattern is consistent with `NamingStrategy` (ADR-014) and `PermissionEvaluator` (ADR-011).

---

*See also: [ADR-019 — Automation Execution Model](ADR-019-automation-execution-model.md), [ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md)*
