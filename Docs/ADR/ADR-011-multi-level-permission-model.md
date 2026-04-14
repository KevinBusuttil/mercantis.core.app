# ADR-011 — Multi-Level Permission Evaluation Model

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe implements a 5+ level permission system: DocPerm (role-based CRUD per DocType with permission levels 0–9), User Permissions (record-level restrictions), sharing, field-level read/write, and workflow action guards. This system is battle-tested but complex and tightly coupled to its server-side architecture.

Mercantis Core needs an equivalent permission model that runs entirely on-device and integrates cleanly with the offline-first document lifecycle.

## Decision

Mercantis Core implements permission evaluation as an **evaluator chain**. Each permission level is a `PermissionEvaluator` protocol conformance:

```swift
protocol PermissionEvaluator {
    func evaluate(context: PermissionContext) -> PermissionDecision
}

enum PermissionDecision {
    case allowed
    case denied(reason: String)
    case abstain
}
```

The chain consists of five evaluators executed in order:

1. **`AppLevelEvaluator`** — Is the user's role allowed to use this module/app at all?
2. **`DocTypeLevelEvaluator`** — `PermissionRule` per role: read, write, create, delete, submit, amend.
3. **`FieldLevelEvaluator`** — `readRoles` / `writeRoles` per field definition.
4. **`RowLevelEvaluator`** — A condition expression filter evaluated by `ExpressionEngine` (e.g. `warehouse == userDefaults.warehouse`).
5. **`WorkflowLevelEvaluator`** — `allowedRoles` on each workflow transition.

All evaluators must return `.allowed` or `.abstain` for an operation to proceed. Evaluation short-circuits on the first `.denied` result. An evaluator that returns `.abstain` defers to the next in the chain.

Each evaluator is independently testable. New evaluators can be appended to the chain without modifying existing ones.

## Consequences

**Positive:**
- Predictable, ordered evaluation: every denial has a clear level and reason.
- Fine-grained access control down to individual fields prevents data leakage in shared DocTypes.
- Consistent enforcement — the same `PermissionEngine` chain is called by DocumentEngine, WorkflowEngine, and the UI Shell.
- Each evaluator is independently testable in isolation.

**Negative:**
- 5-level evaluation adds overhead to every document operation.
- Complex permission configurations are difficult to debug.
- No "sharing" mechanism (planned for a future ADR).

**Neutral:**
- The chain is extensible — new evaluators can be inserted without breaking existing ones.

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md)*
