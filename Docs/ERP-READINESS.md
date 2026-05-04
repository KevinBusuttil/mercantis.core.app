# ERP Readiness — Core Platform

_Last updated: 2026-05-04_

This doc grades `mercantis.core.app` specifically against the requirements of an
ERP host application (the canonical consumer being `mercantis.hub.app`). It is
narrower in scope than [`IMPLEMENTATION-STATUS.md`](IMPLEMENTATION-STATUS.md):
that doc is a complete map of doc-vs-code; this one filters that map through an
"is this enough to build Accounting / Sales / Purchase / Inventory on?" lens
and lists the engine-level gaps Hub will hit if it tries.

For Hub's side of the same conversation see
[`mercantis.hub.app/Docs/ERP-READINESS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/ERP-READINESS.md)
and [`HUB-ON-CORE-PROGRESS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/HUB-ON-CORE-PROGRESS.md).

---

## 1. Headline grade

**Core is ~70% ready as an ERP platform.** The engine layer is well-architected
and the offline-first / metadata-driven / sandboxed-expression / mutation-log
substrate is sound. Most of what remains is either (a) host-app wiring that
Hub will own, (b) ERP-flavoured features that have a place in the architecture
but no implementation yet (Files, Print/PDF, Import/Export), or (c) a small
number of "the type exists but the runtime does not" cases that will bite
the first ERP module to need them.

There are no architectural rewrites required. Every gap below has a clear
landing place in an existing subsystem.

---

## 2. Subsystem scorecard (ERP lens)

Each row asks: _is this subsystem capable enough today for Hub to build
real ERP modules on top of it?_

| Subsystem | Grade | ERP-relevant verdict |
|---|---|---|
| DocumentEngine | ✅ Ready | CRUD, submit/cancel/amend, optimistic concurrency, atomic mutation log all work. The two ERP-relevant gaps are listed in §3 (`list()` capabilities; auto row-level filtering). |
| MetadataEngine | ✅ Ready | DocType + ResolvedMeta + custom fields + property setters cover ERP customisation needs. |
| ExpressionEngine | ✅ Ready | AST + cross-document `lookup()` + parse-cache means automation rules and formula fields will scale to an ERP rule set without re-architecting. |
| Storage | ✅ Ready | GRDB/SQLite + 6 versioned migrations. Proven offline-first substrate. |
| SyncEngine | ⚠️ Partial | Push/pull/conflict-resolution all work; pruning works. **No real `CloudAdapter` implementation** — only `NoOpCloudAdapter`. Multi-device ERP sync is architecturally ready but not connected to any backend. |
| WorkflowEngine | ⚠️ Partial | State machine + role/condition gating work. `WorkflowTransitionHistory` is **returned but not auto-persisted** — Hub will silently lose audit trail unless it stores history itself. |
| PermissionEngine | ⚠️ Partial | DocType / field / row-level checks all work. **`DocumentEngine.list` does not auto-apply `canAccessRow`** — every list call site must remember to pass the row expression. Easy to forget in an ERP with many list views. |
| NamingSystem | ⚠️ Partial | Five strategies ship (UUIDv7, Series, FieldDerived, Prompt, Format). **`DocumentNamingRule` (conditional selector) is missing** — per-company / per-fiscal-year naming series cannot be expressed today. **Counters are local-only** — multi-device sequential naming will collide. |
| AppRuntime | ⚠️ Partial | `AppManifest`, `AppInstaller`, `ExtensionPointResolver` all ship. **Not constructed at app launch** in `mercantis_coreApp.swift`; Hub already does this on its side, but third-party app shells will need the same wiring or a helper. |
| AutomationRunner | ✅ Ready | Action registry + built-in handlers (`set_value`, `set_status`, `send_notification`, `validate`, `assign`) cover the common ERP automation cases. Scheduler-triggered rules (`triggerEvent == "onSchedule"`) are still no-ops — see §3. |
| SchedulerService | ⚠️ Partial | Cron, persistence, tick loop all ship. **Not wired to AutomationRunner**, so manifest-declared scheduled automation rules don't fire. **Background-task budget categories** (`short` / `default` / `long`) **and `audit_log` writes for failed runs** are not implemented. |
| ReportEngine | ⚠️ Partial | `register` / `availableReports` / `execute` exist. **Role filtering is ignored** — `availableReports(for: role)` returns everything. No native renderer yet (`MercantisCoreUI` has no `GenericReportView`). |
| Audit log | ❌ Missing-in-fact | The `audit_log` table is created in migration v1 and **nothing ever writes to it**. Sync queue is acting as a de-facto log, but a financial-grade ERP needs a true append-only audit table with a writer + reader API. |
| Files / Attachments | ❌ Missing | No `Files/` subsystem on disk. Every ERP transactional document needs attachments (scanned invoice, signed PO, photo of damaged shipment). |
| Print / PDF | ❌ Missing | No `Printing/` subsystem. Sales invoices, purchase orders, delivery notes universally require print formats and PDF rendering. |
| ImportExport | ❌ Missing | No `ImportExport/` subsystem. Bulk CSV/JSON import/export is essential for any real deployment (data migration, supplier price lists, opening balances). |
| Notifications | ⚠️ Partial | Typed event bus ships and works. `NotificationLog` DocType, in-app inbox, email/SMS/webhook channels are not implemented. |
| Dashboards | ❌ Missing-runtime | `DashboardDefinition` decodes from manifests. **No `DashboardView` exists** in `MercantisCoreUI`. ERP home screens require dashboards. |
| UIShell | ✅ Ready | `GenericFormView`, `GenericListView`, `NavigationShell`, `FormBuilderView`, link picker, inline child-table editor, rich text / image / barcode field types all ship. |
| SwiftPM split | ✅ Ready | `MercantisCore` (headless) + `MercantisCoreUI` (SwiftUI) means Hub can depend on the right surface cleanly. |

Legend: ✅ Ready · ⚠️ Partial · ❌ Missing

---

## 3. ERP-blocking gaps in detail

These are the gaps most likely to bite Hub as it builds out modules. Each
one has a concrete fix that lands inside an existing subsystem.

### 3.1 `DocumentEngine.list()` is equality-only

**What ships today:** `list(docType:filters:whereExpression:sortBy:limit:offset:)`.
The `filters` parameter takes equality-only `[String: FieldValue]` matches.
Sort, range, LIKE, and IN are not implemented. `whereExpression` covers
arbitrary boolean expressions but runs in-memory after the SQL fetch.

**Why it matters for ERP:** Every ERP list view needs date ranges (open
invoices in Q4), amount filters (POs over €10k), sorting (most recent
first), and IN filters (Sales Invoices for a list of customers).
Today every such list must over-fetch and post-filter, which will not
scale.

**Suggested fix:** Extend `filters` to a typed `[ListFilter]` with
operator (`eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in`, `like`, `between`),
and push to SQL via `json_extract` for fields that match a system column
or a `DocType.IndexDefinition`. Keep the in-memory tail for the rest.

### 3.2 Audit log table is never written

**What ships today:** Migration v1 creates an `audit_log` table.
`DocumentEngine.save / delete / submit / cancel / amend` write the
mutation log but **not** the audit log. There is no reader or writer API.

**Why it matters for ERP:** Financial compliance (SOX, audit trails for
journal entries / GL entries / payment entries) requires an immutable
record of who-changed-what-when that is distinct from the sync queue
(which is operationally pruned — see ADR-028).

**Suggested fix:** Add an `AuditLogWriter` invoked from the same atomic
write block as the mutation-log append. Persist `{id, docType, docId, op,
userId, deviceId, before, after, timestamp}`. Expose a typed reader for
the Hub UI. Honour ADR-028 retention separately (audit log is _not_
pruned by default).

### 3.3 `WorkflowTransitionHistory` is not auto-persisted

**What ships today:** `WorkflowEngine.transition(...)` returns a
`WorkflowTransitionHistory` record and fires a typed event. It does **not**
write the record anywhere. §4.5 of `ARCHITECTURE.md` reads as if it does.

**Why it matters for ERP:** Workflow audit (who approved this PO at what
state, when it was submitted, who cancelled it) is a hard requirement.
If Hub forgets to persist the returned record, the audit is lost.

**Suggested fix:** Persist transition history inside `WorkflowEngine` to
a new `workflow_transitions` table; expose a reader API. The returned
value can stay for callers that want immediate access.

### 3.4 `DocumentEngine.list` does not auto-apply `canAccessRow`

**What ships today:** `PermissionEngine.canAccessRow(...)` works with a
sandboxed boolean expression. Callers of `list()` must pass that
expression themselves via `whereExpression`.

**Why it matters for ERP:** Row-level security ("warehouse manager can
only see their own warehouse's stock entries") is a per-DocType
declaration. Every list call site repeating the row-expression
plumbing is fragile.

**Suggested fix:** Add an optional `DocType.rowAccessExpression: String?`
honoured automatically by `DocumentEngine.list`. The current
`whereExpression` parameter remains for ad-hoc filters.

### 3.5 No real `CloudAdapter` implementation

**What ships today:** `CloudAdapter` protocol + `NoOpCloudAdapter`.

**Why it matters for ERP:** Multi-device, multi-user ERP requires a
real backend. Hub deployments will eventually need at least one
reference adapter (CloudKit, Supabase, S3+JSON, custom REST, etc.).

**Suggested fix:** Out of scope for Core itself per ADR-018 — Core
defines the protocol, host apps implement. But shipping at least one
reference adapter (likely CloudKit) would help Hub's first
multi-device customer.

### 3.6 `DocumentNamingRule` conditional selector missing

**What ships today:** Five naming strategies, but no rule layer that
picks between them based on document field values.

**Why it matters for ERP:** Per-company naming series
(`SINV-ACME-` vs `SINV-WIDGETS-`), per-fiscal-year resets, per-warehouse
GRN numbering — all expressed via conditional rules in ERPNext. None
expressible today in Hub.

**Suggested fix:** Implement `DocumentNamingRule` (priority-ordered,
condition expression + strategy reference) and evaluate in
`NamingService.resolve(...)` before falling through to the DocType's
default `autoname`.

### 3.7 Naming counters are local-only

**What ships today:** `naming_counters(seriesKey, value)` table written
in a short transaction. Single-device only.

**Why it matters for ERP:** Two devices submitting Sales Invoices
offline will pick the same `SINV-2026-0001` and collide on sync
(VCM rejects, but the user experience is bad).

**Suggested fix:** Per ADR-014's open follow-up — per-device range
reservation via the sync queue. Each device claims a block of N
counter values from the cloud; offline issuance draws from the
local block. Reconciles on next sync.

### 3.8 SchedulerService is not wired to AutomationRunner

**What ships today:** Both subsystems exist and tick correctly in
isolation. Manifest `automationRules` with `triggerEvent == "onSchedule"`
parse but never fire because the runner doesn't subscribe to scheduler
ticks.

**Why it matters for ERP:** "Daily — recompute open balance",
"Hourly — pull supplier price feed", "Monthly — close the period" all
need scheduler-driven automation.

**Suggested fix:** `AutomationRunner` registers a single
`ScheduledTask` per cron expression seen in `automationRules`. On tick,
runs the rule's actions through the existing dispatcher.

### 3.9 Files / Print / Import-Export missing

These are documented as planned (P3.1 / P3.2 / P3.3) and won't surprise
anyone, but they are real ERP blockers:

- **Files:** Required by every transactional DocType. Land first.
- **Print / PDF:** Required by Sales Invoice, Purchase Order, Delivery
  Note, Quotation. Land before submitting Selling/Buying modules.
- **Import / Export:** Required by every customer's data migration. Land
  before any production deployment.

### 3.10 Dashboard rendering missing

**What ships today:** `DashboardDefinition` decodes from manifests.
`HubDashboards.swift` already declares dashboards. No view renders them.

**Suggested fix:** Add `GenericDashboardView` to `MercantisCoreUI`
backed by `ReportEngine.execute(...)` for the data tiles. Hub's
`HubMenuItem.dashboard` case in `Navigation/HubNavigation.swift` then
routes to it.

---

## 4. Suggested fix order

A pragmatic sequence that unblocks the most ERP work per unit of Core
effort, ordered to land before Hub's modules need them:

### Phase A — Engine fixes that unblock real list views (do first)

1. **§3.1 `list()` operators + sort + push-to-SQL.** Every module
   benefits immediately.
2. **§3.4 Auto-apply `canAccessRow`.** Cheap to add once §3.1 lands.
3. **§3.3 Persist `WorkflowTransitionHistory`.** Tiny change, large
   compliance payoff.
4. **§3.2 Audit log writer + reader.** Wire into the existing atomic
   write block.

### Phase B — Wiring and naming polish

5. **§3.8 Scheduler ↔ AutomationRunner.** Unlocks scheduled rules.
6. **§3.6 `DocumentNamingRule`.** Unlocks per-company naming series.
7. **§3.7 Counter range reservation.** Required before any production
   multi-device deployment.

### Phase C — ERP feature breadth

8. **Files / Attachments (P3.1).** Required by every ERP DocType with
   external paperwork.
9. **Print / PDF (P3.2).** Required before Selling / Buying modules
   ship to a customer.
10. **Dashboard rendering (§3.10).** Hub already declares dashboards
    that have nowhere to render today.
11. **Import / Export (P3.3).** Required before any real-world
    deployment.

### Phase D — Production readiness

12. **At least one real `CloudAdapter` implementation (§3.5).**
13. **`NotificationLog` + at least one channel** (in-app inbox or
    email).
14. **`ReportEngine` role filtering** + a `GenericReportView` in
    `MercantisCoreUI` (Hub Wall 9).

---

## 5. What Core does _not_ need to do

To keep this doc honest about scope:

- ERP _domain_ DocTypes (Customer, Item, Sales Invoice, GL Entry, …) live
  in Hub, not Core. ADR-001 / ADR-007 are the contract.
- The `MercantisCLI` install / patch flow already shares one pipeline with
  the in-app installer (P2.3); no further work needed here.
- The SwiftPM split (`MercantisCore` vs `MercantisCoreUI`) is already
  consumable from Hub; the Xcode app target migrating onto the SwiftPM
  libraries is a `.pbxproj` chore, not an architectural item.

---

## 6. Cross-references

- [`IMPLEMENTATION-STATUS.md`](IMPLEMENTATION-STATUS.md) — full doc-vs-code
  reconciliation.
- [`ENHANCEMENT-PROPOSAL.md`](ENHANCEMENT-PROPOSAL.md) — the P-numbered
  enhancement roster referenced throughout this doc.
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — full architecture document.
- [`ADR/`](ADR/) — the architecture decision records that pin the
  contracts referenced above.
- Hub-side: [`HUB-ON-CORE-PROGRESS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/HUB-ON-CORE-PROGRESS.md)
  — what Hub has adopted and where its walls (W4–W9) intersect Core's
  capabilities.
- Hub-side: [`ERP-READINESS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/ERP-READINESS.md)
  — Hub's own ERP module-coverage scorecard.
