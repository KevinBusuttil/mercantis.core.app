# ADR-029 — Cross-Document `lookup()` in the Expression Engine

**Status:** Accepted
**Date:** 2026-04-25

---

## Context

The sandboxed `ExpressionEvaluator` (ADR-017) evaluates boolean
conditions and formula values against a `[String: FieldValue]` context
that contains exactly one document's fields. This is enough for
visibility expressions, single-document validation rules, and
formula fields that derive a value from sibling fields on the same
document. It is not enough for any of the following common ERP
patterns:

- "Set the row total from `lookup("Item", item_code, "rate") * qty`."
- "Block submit unless `lookup("Customer", customer, "credit_limit") > total`."
- "Visibility: `lookup("Settings", "default", "show_advanced") == true`."

Frappe ships `frappe.db.get_value(doctype, name, fieldname)` for this
purpose. P2.2 in `Docs/ENHANCEMENT-PROPOSAL.md` carried the same
feature as a placeholder ("frequently requested Frappe feature; needs
an ADR; cache-by-read with per-save invalidation is the recommended
direction"). This ADR resolves it.

The AST work in P2.1 already shipped a `.call` node and parser
support for `identifier(args)` syntax. The interpreter rejected every
call name. That left a clean place to plug in `lookup`.

## Decision

The expression engine recognises one named call: `lookup(docType,
name, field)`. The shape is fixed:

- `docType` must evaluate to a non-empty string. Idiomatically a
  string literal (`"Item"`).
- `name` may evaluate to a string, `null`, or an undefined identifier.
  A null/undefined name resolves to `null` (so
  `lookup("Item", optional_link, "rate")` is safe on draft documents
  where the link is unset).
- `field` must evaluate to a non-empty string. Idiomatically a string
  literal (`"rate"`).

`lookup(...)` returns the resolved field's `FieldValue`, mapped through
the same `fieldValueToRuntime` path as a regular field reference, so
typed dates compare as epoch seconds, opaque values map to `.null`,
and arithmetic / comparison work without a special case. A missing
document or missing field both resolve to `.null`.

### Resolver injection (`DocumentLookupResolver`)

```swift
public protocol DocumentLookupResolver: AnyObject {
    func lookup(docType: String, name: String, field: String) throws -> FieldValue?
}
```

`ExpressionEvaluator.init` takes an optional `lookupResolver:
DocumentLookupResolver?`. When `nil` (the default — every existing
call site keeps working unchanged), `lookup(...)` throws
`unexpectedToken("call to 'lookup' is not supported in this
evaluator")` so the absence is loud, not silent. When set, the
evaluator dispatches to the resolver.

`DocumentEngine` is the reference resolver. Conformance is via an
extension that calls `fetch(docType:id:)`; permission, soft-delete,
and index behaviour stay consistent because lookup reads through the
same SQL path everything else does.

### Caching: `CachingDocumentLookupResolver`

The proposal called for "cache-by-read with per-save invalidation
(already how `MetaComposer` works)". The cache wraps a base resolver
and exposes the same `DocumentLookupResolver` surface:

- **Read-through.** A successful (or empty) lookup is memoized in
  `[CacheKey: [String: FieldValue?]]` where `CacheKey` is
  `(docType, name)`. The inner `FieldValue?` preserves the
  distinction between "looked up and the field is absent" (cached as
  `nil`) and "never looked up" (no entry).
- **Per-save invalidation.** Constructed with an `EventEmitter`, the
  resolver subscribes to `DocumentSavedEvent`,
  `DocumentDeletedEvent`, `DocumentSubmittedEvent`, and
  `DocumentCancelledEvent`. On any event for `(docType, id)` it
  drops every cached field for that key. `DocumentAmendedEvent` is
  intentionally ignored — amend creates a new id (no cache entries
  to drop) and leaves the original unchanged.
- **Process-local.** Cross-device invalidation is implicit: a remote
  write that arrives via `SyncEngine` lands through
  `DocumentEngine.applyRemote(_:from:)` (P0.2), which fires the same
  `DocumentSavedEvent`. Devices observe each other's writes through
  their own engine's event stream.
- **Weak base.** The cache holds `base` weakly so a typical
  `DocumentEngine` → `CachingDocumentLookupResolver` → engine
  ownership shape doesn't form a retain cycle.

`DocumentEngine` exposes `lookupCache: CachingDocumentLookupResolver`
and a `listExpressionEvaluator: ExpressionEvaluator` pre-wired with
the cache. `DocumentEngine.list`'s `whereExpression` runs against
this evaluator, so list filters can call `lookup(...)` to filter on
parent-document field values, and the join is memoized once per
parent (not per row).

### DoS / ADR-008 protection

`ExpressionEvaluator.lookupBudget` (default 32) caps the number of
`lookup(...)` calls a single top-level evaluation may make. Excess
calls throw `EvaluatorError.lookupBudgetExceeded(limit:)`. The cap
defends against expressions that would otherwise issue an unbounded
number of cross-document reads per evaluation — consistent with the
"no resource exhaustion by design" posture of ADR-017 / ADR-008.
Setting `lookupBudget: 0` disables `lookup(...)` even when a resolver
is supplied; `Int.max` lifts the cap.

### Error handling

- Wrong arity → `unexpectedToken("lookup() requires exactly 3
  arguments (docType, name, field)")`.
- Non-string `docType` / `field` → `typeMismatch(...)`.
- Resolver throw → caught and surfaced as `.null`. A transient
  storage error should not crash an entire form's expression
  evaluation; permission and budget decisions surface as their own
  typed throws above the catch.

## Consequences

**Positive:**

- The evaluator now covers the vast majority of cross-document
  expressions that a Frappe app would express via
  `frappe.db.get_value` — without enlarging the evaluator's syntax
  surface (it's just a call form the AST already supported).
- Hot paths (a `whereExpression` over many rows, an automation rule
  that joins through the same parent on every save) memoize the
  joined value via the engine's `lookupCache`. The amortized cost is
  one fetch per `(docType, id)` pair per write cycle.
- `lookup(...)` is opt-in by injection: existing
  `ExpressionEvaluator()` construction sites stay sandboxed exactly
  as before.
- The cache is process-local and self-coherent — no separate
  invalidation API to remember to call. Every write path through
  `DocumentEngine` already publishes the events the cache subscribes
  to.

**Negative:**

- The evaluator can now make I/O (one DB read per uncached
  `lookup`). Profiling for hot paths is now meaningful in a way it
  wasn't for the pure-CPU evaluator.
- A misconfigured cache that subscribes to a different
  `EventEmitter` than the engine publishes on will return stale
  reads forever. Tests that inject a fresh emitter per harness need
  to thread it consistently through both sides.
- Static `referencedFields(in:)` analysis sees the `name` argument
  as a referenced field of the *current* DocType (correct — that's
  the typical idiom), but does not record that the expression also
  reads `(docType, field)` from another DocType. A future static
  analysis enhancement could surface those cross-DocType
  dependencies.

**Neutral:**

- `lookup` is the only recognised call name. The AST keeps the
  general `.call(name, args, range)` shape so adding more (e.g. a
  `has_role` predicate, deferred from ADR-011 / P1.7) does not
  require a syntax change.
- The cache is unbounded today. A typical write pattern keeps the
  working set small (one entry per linked parent), but a
  long-running process that lookups many distinct ids without ever
  invalidating them could grow the map. Adding an LRU bound is a
  future tweak gated on real measurement.
- The evaluator's `lookupBudget` is per-evaluation, not
  per-document-save. An automation rule that runs on every save and
  uses lookup once per fire is not budget-bound across saves; only a
  single evaluation that loops via nested calls is.

---

*See also:
[ADR-008 — No Arbitrary Downloaded Executable Plugins on iOS](ADR-008-no-executable-plugins-ios.md),
[ADR-017 — Expression Engine Scope and Sandboxing](ADR-017-expression-engine-scope-sandboxing.md),
[ADR-021 — Metadata Composition and Resolved Meta](ADR-021-metadata-composition-resolved-meta.md),
[ADR-024 — Document Versioning and Field-Level Diff Tracking](ADR-024-document-versioning-diff-tracking.md).*
