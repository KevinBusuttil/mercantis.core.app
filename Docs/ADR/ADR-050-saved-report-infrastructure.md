# ADR-050 — Generic Saved-Report Infrastructure

**Status:** Accepted
**Date:** 2026-06-02

---

## Context

Core already had fixed, app-declared reports: a `ReportDefinition`
(columns + filters + `allowedRoles`) registered in an `AppManifest`,
executed by `ReportEngine.execute(report:)` into a `ReportResult`, and
rendered by `GenericReportView` (ADR-049).

What it did **not** have was any notion of a *user-created* or
*user-customised* report variant. A user could not:

- hide or reorder columns on a report,
- save their own filter defaults,
- store a preferred sort order,
- keep a private/shared variant of a built-in report.

Every report was hardcoded by the app author. Hub wants to let users
customise report columns, filters, sorting, and saved views — but the
*mechanism* for that is generic and belongs in Core, not in any one app.

## Decision

Add a generic, app-neutral saved-report layer to Core, in
`mercantis core/Reporting/`:

### Model — `SavedReportDefinition`

A data-only, `Codable` value type. It carries **no** SQL, no
expressions, and no script — only structured configuration:

| Field | Purpose |
|---|---|
| `id` | stable identifier |
| `name` | display name |
| `baseReportId?` | the built-in `ReportDefinition` it was cloned from, if any |
| `sourceDocType` | the DocType queried |
| `ownerUserId` | the owning user |
| `visibility` | `.private` / `.shared` |
| `columns` | `[SavedReportColumn]` |
| `filters` | `[SavedReportFilter]` |
| `sorts` | `[SavedReportSort]` |
| `createdAt` / `updatedAt` | timestamps |

- **`SavedReportColumn`** — `fieldKey`, `labelOverride?`, `visible`,
  `order`, `width?`. Visibility toggles a column without losing its
  config; `order` drives left-to-right placement.
- **`SavedReportFilter`** — `fieldKey`, `operator`, `value?`,
  `defaultValue?`, `required`. The operator is a closed enum
  (`equals`, `notEquals`, the four comparisons, `contains`, `isNull`,
  `isNotNull`) that maps 1:1 onto the existing typed `ListFilter.Op`.
- **`SavedReportSort`** — `fieldKey`, `direction`.

`Codable` decode is lenient (missing `visibility`, collections, and
timestamps fall back to defaults) so stored payloads survive schema
growth.

### Conversion from a built-in report

`SavedReportDefinition.from(reportDefinition:ownerUserId:…)` (and the
engine's `convert(_:ownerUserId:…)` convenience) clone a built-in
`ReportDefinition` into editable saved configuration: every declared
column becomes a visible column in declaration order, every declared
filter becomes an optional saved filter seeded with the built-in's
default, and `baseReportId` records the origin.

### Execution — `SavedReportEngine`

`SavedReportEngine.execute(savedReport:requestingUserId:runtimeFilterValues:userRoles:)`
returns a normal `ReportResult` and enforces the safety rules:

1. **Ownership/visibility gate.** A `.private` report is reachable only
   by its owner; `.shared` by anyone.
2. **Field allow-listing.** Every referenced `fieldKey` (column, filter,
   sort) must exist in the source DocType metadata or be a known
   document system column (`id`, `status`, `createdAt`, …). Unknown
   fields are rejected — a saved report can't reach beyond its declared
   surface.
3. **No arbitrary code.** Filters compile to typed `ListFilter`
   predicates; there is no SQL string and no Swift/script path.
4. **Permissions preserved.** Queries run through
   `DocumentEngine.list`, so DocType `rowAccessExpression` and
   role-based row filtering (ADR-037) still apply — a saved report can
   never widen access beyond what the requesting user could already
   see.

Effective filter value resolves as
`runtime override → stored value → defaultValue`; a `required` filter
with no effective value is a hard error.

The built-in `ReportEngine` path is untouched. Both engines now format
cells through a shared `ReportValueFormatter`, so a column value looks
identical regardless of which engine produced it.

## Consequences

**Positive**

- Apps get user-customisable reports (column show/hide, reordering,
  saved filter defaults, stored sorts, private/shared variants) without
  hardcoding report variants.
- The model is app-neutral; Hub layers its ERP reports on top without
  Core learning any ERP concepts.
- Reuses the existing typed `ListFilter`/`ListSort` surface and
  row-access enforcement, so no new query or permission path is
  introduced.

**Negative / limits (deliberately out of scope)**

- No pivot tables, charts, grouping, scheduled email, or arbitrary-SQL
  editor — the `ReportResult` shape leaves room to add those later
  without changing this model.
- Sharing is a simple two-state `private`/`shared` flag; there is no
  per-role grant list and no cross-company security model.
- Persistence of saved reports is left to the host (the engine keeps an
  in-memory registry mirroring `ReportEngine`); a DocType-backed store
  can be a follow-up if needed.

**Neutral**

- `userRoles: Set<String>` matches the engine's existing role-set API,
  keeping role-set composition uniform.

## Core / Hub boundary

This infrastructure is **reusable plumbing** and lives in
`mercantis.core.app`. It defines *how* a report can be customised, not
*which* reports exist.

| Lives in Core (this ADR) | Lives in Hub (follow-up) |
|---|---|
| `SavedReportDefinition` + column/filter/sort value types | Concrete saved reports (Sales Register, VAT Summary, Stock Ledger, …) |
| `SavedReportEngine` (validate, convert, execute) | ERP DocTypes the reports target |
| Generic visibility / ownership metadata | Hub navigation entries and report screens |
| Field allow-listing against DocType metadata | Cross-company / org-specific access policy |

Core must not gain ERP-specific report names, ERP DocTypes, VAT/stock/
sales/POS reports, or Hub navigation. Hub integration is a separate
follow-up issue built on this foundation.
