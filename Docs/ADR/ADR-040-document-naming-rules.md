# ADR-040 — `DocumentNamingRule` Conditional Selector

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

A DocType can declare a single `autoname` strategy (UUID, naming series,
field-derived, etc.). Real ERPs need *conditional* naming:

- Per-company series: `SINV-ACME-` for company "ACME",
  `SINV-WIDGETS-` for company "WIDGETS".
- Per-fiscal-year resets: a different series each fiscal year.
- Per-warehouse GRN numbering: `GRN-WH01-`, `GRN-WH02-`.

ERPNext expresses these via a priority-ordered rule list that maps a
condition to a naming spec. Mercantis Core had no equivalent.

## Decision

Add `DocumentNamingRule(id, priority, condition, autoname)`. Rules live
on the DocType:

```swift
public var namingRules: [DocumentNamingRule]
```

`NamingService.resolve(...)` evaluates the rules in ascending `priority`
order:

1. The first rule whose `condition` evaluates to `true` against
   `document.fields` wins; its `autoname` spec is used in place of
   `DocType.autoname`.
2. A `nil` / empty / whitespace-only `condition` matches every document
   (catch-all, useful as a final-priority fall-through).
3. A condition that fails to evaluate (parse error, type mismatch) is
   skipped fail-closed; evaluation continues with the next rule.
4. If no rule matches, `NamingService` falls through to
   `DocType.autoname`, then to `UUIDv7Strategy` if that is also absent.

Conditions evaluate through the same `ExpressionEvaluator` used for
visibility / readonly / row-access expressions, so the language is
identical and the parse cache is shared.

## Consequences

**Positive**

- ERPnext-style per-company / per-fiscal-year / per-warehouse naming is
  expressible in metadata without code changes.
- Backward compatible: DocTypes without `namingRules` keep the legacy
  single-`autoname` behaviour byte-for-byte.

**Negative**

- A rule can fail closed silently if its expression doesn't parse,
  hiding the bug. The Schema validator's expression check (P2.1) does
  not currently extend to `namingRules.condition`; recommended follow-up.
- Priority is integer, not name-keyed — duplicate priorities resolve
  by declaration order, which is fine but worth documenting.

**Neutral**

- Conditions can reference any field on the document. They cannot
  reference `user.*` or call `lookup(...)` today (that would require a
  `DocumentLookupResolver` on the `NamingService`); deferred until
  there is a real ERP need.
