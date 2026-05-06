# ADR-045 — Dashboard Runtime

**Status:** Accepted
**Date:** 2026-05-05

---

## Context

`DashboardDefinition` and `DashboardWidget` have decoded from app
manifests since ADR-004, but no runtime evaluated them. STATUS.md §3.10
flagged this: Hub already declares dashboards in
`HubDashboards.swift`, and the declarations have nowhere to render.

Three concerns to separate:

1. **Data resolution.** Walk the widget list, run each widget's
   underlying query (count / list / chart / shortcut), produce
   a typed result.
2. **Rendering.** Turn the typed result into pixels. SwiftUI is the
   right home for this — but it lives in `MercantisCoreUI`, not the
   engine library.
3. **Error handling.** A broken widget should not blank the entire
   dashboard.

## Decision

`DashboardEngine` lives under `mercantis core/Reporting/` (alongside
`ReportEngine`, since chart widgets defer to it). It owns:

- A registry of `DashboardDefinition`s.
- The `resolve(dashboardId:userRoles:)` method that walks the
  declaration's widgets and produces a `DashboardResult`.
- A typed `DashboardWidgetResult` enum mirroring the four widget
  kinds plus an `error` case carrying a human-readable reason.

Widget resolution rules:

- **count** — calls `DocumentEngine.list(...)` with optional
  parameter-derived predicates and returns the row count.
- **list** — same, with explicit `columns` / `limit` parameters and
  per-column value extraction via `PrintTemplate.lookup`.
- **chart** — defers to `ReportEngine.execute(report:)` so charts
  share their data path with reports.
- **shortcut** — returns the navigation target straight from the
  declaration (no DB hit).

Widget parameter syntax (CSV-style; kept manifest-friendly):

- `status=Open` ⇒ equality predicate.
- `where.<field>__<op>=<value>` ⇒ typed operator predicate
  (`eq`/`neq`/`gt`/`gte`/`lt`/`lte`/`like`/`isnull`/`notnull`).
  Reuses Phase A's `ListFilter` predicates (ADR-036).

## Consequences

**Positive**

- Hub's `HubDashboards.swift` declarations now have a real runtime to
  consume. Pixel rendering still belongs to `MercantisCoreUI`, but the
  engine no longer leaves declared dashboards as dead weight.
- Per-widget error isolation: one bad widget shows an error tile, the
  rest of the dashboard renders.
- Charts share the `ReportEngine` execution path, so their data
  semantics are identical to running the same report on its own.

**Negative**

- The widget parameter grammar is intentionally narrow. Anything
  beyond simple operator predicates needs a richer schema (or a
  `whereExpression` parameter). Deferred until ERP module rules
  demand it.
- `applyRowAccess: false` is hard-coded for the `list`/`count`
  widget queries. Dashboards run as a system actor so the count
  matches reality; per-user "what I can see" dashboards need an
  explicit user-roles override path. Acceptable for now; documented
  as a follow-up.
- The `widget.parameters` dictionary is `[String: String]` per
  ADR-004's manifest contract. Numeric / typed parameters get
  coerced inside `DashboardEngine` rather than at decode time.

**Neutral**

- `GenericDashboardView` (the SwiftUI consumer of `DashboardResult`)
  ships with `MercantisCoreUI` in a follow-up; the engine library
  contract is the typed result.
