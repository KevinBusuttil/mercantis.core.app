# ADR-049 — `ReportEngine` Role Filtering + `GenericReportView`

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`ReportEngine.availableReports(for: userRoles)` had a `userRoles`
parameter since day one but ignored it — every registered report was
returned to every caller. Hub's Wall 9 (HUB-STATUS.md) needed two
things to ship its first reports:

1. A way to declare "Sales Manager only" / "HR only" reports without
   wrapping every call site in role-aware code.
2. A SwiftUI view in `MercantisCoreUI` that consumes a `ReportResult`
   and renders it without per-report code.

## Decision

**Engine side.** `ReportDefinition` gains an optional
`allowedRoles: [String]?`. Visibility rule:

- `nil` or empty list → every role can see the report (back-compat
  default; existing manifests round-trip unchanged).
- non-empty → at least one role in `userRoles` must intersect
  `allowedRoles`.

`ReportEngine.availableReports(for:)` filters by this rule and sorts
results by `name` for deterministic UI ordering.

`Codable` decode is lenient: legacy manifests without an
`allowedRoles` key decode with `allowedRoles = nil`.

**UI side.** `GenericReportView` ships under `MercantisCoreUI`. It
takes a `title` and a `ReportResult`, and renders:

- A header row with the title, total row count, and optional
  Refresh / Export-CSV buttons (caller-supplied closures).
- An empty-state placeholder for zero-row results.
- A scrollable two-axis table: the result's `columns` form headers,
  rows are striped for readability, missing cells render `—`.

The view is intentionally read-only: filter chips, sort handles, and
drill-throughs belong to the host (Hub) screen that owns the report's
filter state and re-execution loop.

## Consequences

**Positive**

- Hub's first report views (Sales Register, Customer Aging, Stock
  Ledger View, Trial Balance — gated to Accounting / Sales
  Manager / Stock User roles) work without per-report SwiftUI code.
- Role filtering is a single-line declaration on each report; no
  per-call permission plumbing is required.
- The view is decoupled from the engine: callers can drive their
  own state and filters and pass an arbitrary `ReportResult`.

**Negative**

- Role filtering happens after `register(_:)` — a denied user
  cannot tell whether the report exists at all. Acceptable for
  visibility hiding; tighter access control (e.g. forbidding
  `execute(report:)` for unauthorised callers) can be a follow-up
  if Hub needs it.
- `GenericReportView` is a flat table. Pivot, group-by, chart, and
  drill-through views need their own implementations. The
  `ReportResult` shape is sufficient for those views to be added
  later without changing the engine.

**Neutral**

- `userRoles: Set<String>` semantics match `PermissionEngine`'s
  existing role-set API, so role-set composition stays uniform
  across the engine.
- Sort order is `name`-ascending. Hosts that want different
  orderings can re-sort; the engine's order is documented.

## Update — report-view polish (2026-06-03)

Follow-up refinements after Hub started rendering user-customised and
from-scratch reports through this view:

- **`GenericReportView` top-aligns its content.** The body now fills the
  available space and pins the header + table to the top, instead of letting
  a short table float in the vertical centre.
- **`showsTitle: Bool = true`.** Hosts that already display the report name
  (e.g. in a navigation bar) can pass `showsTitle: false` to drop the
  duplicate in-view title while keeping the row count and Refresh /
  Export-CSV actions. Default `true` keeps every existing call site
  unchanged.
- **`ReportResult.csvString()`** moves CSV serialisation into `MercantisCore`
  (RFC-4180 escaping). It lives in the engine layer, not the UI layer, so the
  CLI / headless exporters can produce CSV without importing SwiftUI; the host
  app still owns how the file is delivered (save panel, share sheet).
