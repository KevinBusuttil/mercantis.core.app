# ADR-036 — Typed `ListFilter` Operator Surface

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`DocumentEngine.list(...)` originally accepted `filters: [String: FieldValue]`
where every entry meant strict equality. Real ERP list views need date ranges
("open invoices in Q4"), numeric thresholds ("POs over €10k"), substring
matches ("supplier name LIKE 'Acme%'"), set inclusion ("invoices for these 50
customers"), and null/non-null checks. With only equality, every list call
either over-fetched and post-filtered in Swift or skipped the engine entirely
— neither scales.

Whatever shape we pick has to live cleanly alongside two existing surfaces:

- `whereExpression: String?` — sandboxed boolean expression, runs in memory.
- `filters: [String: FieldValue]?` — equality dictionary, used by Reporting
  and a handful of UIShell call sites.

## Decision

Add a typed `ListFilter` predicate alongside the legacy `filters` dict.

```swift
public struct ListFilter: Sendable {
    public enum Op: Sendable {
        case eq, neq, gt, gte, lt, lte           // each carrying a FieldValue
        case between(FieldValue, FieldValue)     // inclusive
        case `in`([FieldValue])                  // empty IN matches nothing
        case like(String)                        // SQL `%`/`_` wildcards
        case isNull, isNotNull
    }
    public let fieldKey: String
    public let op: Op
}
```

`DocumentEngine.list(...)` gains an optional `predicates: [ListFilter]?`
parameter, AND-combined with `filters` and `whereExpression`. Pushdown rules:

- **System columns** (`id`, `status`, `createdAt`, `updatedAt`, `docStatus`,
  …) compile to a direct column predicate.
- **Indexed user fields** (`DocType.indexes`) compile to
  `json_extract(payload, '$.<key>') <op> ?`.
- **Anything else** falls back to a per-row in-memory evaluator that mirrors
  the SQL semantics, so behaviour is identical regardless of pushdown.

`neq` deliberately matches NULL rows as well as `value != ?`, mirroring
ERPNext's "not equal" semantics so callers do not have to remember to OR
`isNull` manually.

## Consequences

**Positive**

- Every operator a real ERP list view needs is expressible without changing
  the row fetch contract. Pushdown is automatic for fields that opt into an
  `IndexDefinition`.
- The legacy `filters: [String: FieldValue]` parameter still works — existing
  call sites (Reporting, UIShell builders, tests) need no changes.
- `whereExpression` is unchanged; it remains the right tool for cross-field
  boolean logic the operator surface can't express.

**Negative**

- Two filter surfaces (`filters` dict, `predicates` array) overlap on
  equality. We documented `predicates` as the preferred shape for new code
  and kept `filters` for backward compatibility; we do not plan to delete it.
- In-memory `LIKE` is implemented via `NSRegularExpression`, so its
  case-sensitivity matches Swift defaults rather than SQLite's NOCASE rules.
  Indexed-field `LIKE` is pushed to SQL and follows SQLite semantics.

**Neutral**

- `IN ([])` short-circuits to a tautologically-false predicate. This matches
  SQL semantics ("no element in an empty set") rather than ERPNext's "no
  filter applied".
