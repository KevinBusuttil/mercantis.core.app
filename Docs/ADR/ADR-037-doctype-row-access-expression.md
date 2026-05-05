# ADR-037 — DocType-Level `rowAccessExpression` Auto-Filter

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`PermissionEngine.canAccessRow(...)` (P1.7) already evaluates a sandboxed
boolean expression against a document's fields plus a `user.*` namespace.
However, calling it was the caller's responsibility — every `list()` call
site had to remember to pass `whereExpression` correctly, and the row-access
predicate was indistinguishable from any other ad-hoc filter. In an ERP with
dozens of list views, that is a guaranteed accident waiting to happen.

## Decision

Add `rowAccessExpression: String?` to `DocType`. When non-nil, every result
returned by `DocumentEngine.list(...)` is automatically filtered through
`PermissionEngine.canAccessRow(...)` using the supplied (or defaulted)
`userRoles`, `userId`, and `userAttributes`. Callers can still pass an
ad-hoc `whereExpression`; the two AND together.

Per-call escape hatch: `applyRowAccess: false` skips the auto-filter (used
for maintenance / migration paths).

The expression sees:
- every entry in `document.fields`,
- `user.id` from the explicit `listUserId` argument or the engine's `userId`,
- `user.roles` as a sorted array of role names,
- any caller-supplied `userAttributes` namespaced under `user.*`.

Examples:

```
rowAccessExpression: "owner == user.id"
rowAccessExpression: "warehouse == user.warehouse"
rowAccessExpression: "company == user.company || \"System Manager\" in user.roles"
```

## Consequences

**Positive**

- Row-level security is declared once on the DocType and enforced uniformly
  by every `list()` caller. Hub does not have to plumb permission predicates
  through every UI surface.
- Co-existence with `whereExpression` means ad-hoc filters and security
  predicates compose correctly — neither replaces the other.
- The `applyRowAccess: false` escape hatch keeps maintenance and admin
  flows unblocked while keeping the default safe.

**Negative**

- Filtering happens **after** the SQL fetch (the expression is sandboxed
  Swift, not SQL). Large tables with restrictive row-access expressions
  will over-fetch. A future optimisation could compile a subset of
  expressions to SQL `WHERE` clauses; out of scope here.
- Expression failures fall closed (deny). This is the safe default but
  means a malformed expression silently hides every row until fixed.

**Neutral**

- The expression evaluates with the same `ExpressionEvaluator` the rest of
  the engine uses, so cross-document `lookup(...)` is available
  (subject to the per-evaluation lookup budget).
