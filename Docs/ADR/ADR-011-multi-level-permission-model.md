# ADR-011 — Multi-Level Permission Evaluation Model

**Status:** Accepted  
**Date:** 2026-04-14

---

## Context

Frappe implements a 5+ level permission system: DocPerm (role-based CRUD per DocType with permission levels 0–9), User Permissions (record-level restrictions), sharing, field-level read/write, and workflow action guards. This system is battle-tested but complex and tightly coupled to its server-side architecture.

Mercantis Core needs an equivalent permission model that runs entirely on-device and integrates cleanly with the offline-first document lifecycle.

## Decision

Mercantis Core implements a 5-level permission model evaluated in strict order:

1. **App-level** — Is the user's role allowed to use this module/app at all?
2. **DocType-level** — `PermissionRule` per role: read, write, create, delete, submit, amend.
3. **Field-level** — `readRoles` / `writeRoles` per field definition.
4. **Row-level** — A condition expression filter evaluated by `ExpressionEngine` (e.g. `warehouse == userDefaults.warehouse`).
5. **Workflow action level** — `allowedRoles` on each workflow transition.

All levels must pass for an operation to be allowed. Evaluation short-circuits on the first denial.

## Consequences

**Positive:**
- Predictable, ordered evaluation: every denial has a clear level and reason.
- Fine-grained access control down to individual fields prevents data leakage in shared DocTypes.
- Consistent enforcement — the same `PermissionEngine` is called by DocumentEngine, WorkflowEngine, and the UI Shell.

**Negative:**
- 5-level evaluation adds overhead to every document operation.
- Complex permission configurations are difficult to debug.
- No "sharing" mechanism (planned for a future ADR).

**Neutral:**
- The model is extensible — new permission levels can be inserted without breaking existing ones.

---

*See also: [ADR-003 — Metadata-Defined DocTypes](ADR-003-metadata-defined-doctypes.md)*
