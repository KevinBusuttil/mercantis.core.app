# Mercantis Core — Status & Roadmap

_Last updated: 2026-05-05 (Phase C — files/attachments, print/PDF, dashboards, import/export)_

This document consolidates `ERP-READINESS.md` and `IMPLEMENTATION-STATUS.md` into a single reference.
The Enhancement Backlog (former `ENHANCEMENT-PROPOSAL.md`) has been renamed to [`ROADMAP.md`](ROADMAP.md).

- **ERP Readiness** — how ready is the engine for Hub to build real ERP modules on top of it?
- **Implementation Status** — candid doc-vs-code map for the entire codebase.

ADRs are tracked separately in `Docs/ADR/`. Examples live in `Docs/Examples/`.
Architecture revision history lives in `Docs/ARCHITECTURE-CHANGELOG.md`.

Hub-side companion: [`mercantis.hub.app/Docs/HUB-STATUS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/HUB-STATUS.md).

---

# ERP Readiness — Core Platform

_Last assessed: 2026-05-04_

This section grades `mercantis.core.app` against the requirements of an ERP host application
(the canonical consumer being `mercantis.hub.app`). It filters the Implementation Status
section below through an “is this enough to build Accounting / Sales / Purchase / Inventory on?” lens.

---

## 1. Headline grade

**Core is ~90% ready as an ERP platform.** Phase A closed the four engine
gaps; Phase B closed the three wiring-and-naming items; Phase C (this
revision) ships the four "ERP feature breadth" items — file attachments
with on-disk store + cascade-on-delete, declarative print formats with
plain-text and CoreGraphics PDF renderers, a dashboard runtime that
resolves widget declarations into typed result tiles, and a CSV/JSON
bulk import/export subsystem routed through the document validation
pipeline. What remains is Phase D production-readiness: at least one
real `CloudAdapter`, `NotificationLog` channels, and `ReportEngine`
role filtering with a `GenericReportView` in `MercantisCoreUI`.

There are no architectural rewrites required. Every gap below has a clear
landing place in an existing subsystem.

---

## 2. Subsystem scorecard (ERP lens)

Each row asks: _is this subsystem capable enough today for Hub to build
real ERP modules on top of it?_

| Subsystem | Grade | ERP-relevant verdict |
|---|---|---|
| DocumentEngine | ✅ Ready | CRUD, submit/cancel/amend, optimistic concurrency, atomic mutation log, typed `ListFilter` operator surface (Phase A §3.1, ADR-036), and auto-applied row-level access (Phase A §3.4, ADR-037) all ship. |
| MetadataEngine | ✅ Ready | DocType + ResolvedMeta + custom fields + property setters cover ERP customisation needs. `DocType.rowAccessExpression` (ADR-037) added in Phase A. |
| ExpressionEngine | ✅ Ready | AST + cross-document `lookup()` + parse-cache means automation rules and formula fields will scale to an ERP rule set without re-architecting. |
| Storage | ✅ Ready | GRDB/SQLite + 10 versioned migrations (v8 `workflow_transitions`, v9 `naming_counter_blocks`, v10 `attachments`). Proven offline-first substrate. |
| SyncEngine | ⚠️ Partial | Push/pull/conflict-resolution all work; pruning works. **No real `CloudAdapter` implementation** — only `NoOpCloudAdapter`. Multi-device ERP sync is architecturally ready but not connected to any backend. |
| WorkflowEngine | ✅ Ready | State machine + role/condition gating + auto-persisted `WorkflowTransitionHistory` (Phase A §3.3, ADR-038, table `workflow_transitions`). Reader API exposed via both `WorkflowTransitionHistoryWriter` and `DocumentEngine.workflowTransitions(...)`. |
| PermissionEngine | ✅ Ready | DocType / field / row-level checks all work. `DocumentEngine.list` now auto-applies `canAccessRow` via `DocType.rowAccessExpression` (Phase A §3.4, ADR-037). Per-call `applyRowAccess: false` opt-out preserved for admin paths. |
| NamingSystem | ✅ Ready | Five strategies ship + conditional `DocumentNamingRule` selector (Phase B §3.6, ADR-040) + per-device counter block reservation (Phase B §3.7, ADR-042). Multi-device offline saves no longer collide on `SINV-2026-0001`-style series. |
| AppRuntime | ⚠️ Partial | `AppManifest`, `AppInstaller`, `ExtensionPointResolver` all ship. **Not constructed at app launch** in `mercantis_coreApp.swift`; Hub already does this on its side, but third-party app shells will need the same wiring or a helper. |
| AutomationRunner | ✅ Ready | Action registry + built-in handlers + `onSchedule` rules (Phase B §3.8, ADR-041). Scheduled rules iterate every document of the rule's DocType per tick, evaluate the condition per document, and run actions on matches. |
| SchedulerService | ✅ Ready | Cron, persistence, tick loop, and `AutomationRunner` integration (Phase B §3.8). Manifest-declared `onSchedule` automation rules now fire as expected. |
| ReportEngine | ⚠️ Partial | `register` / `availableReports` / `execute` exist. **Role filtering is ignored** — `availableReports(for: role)` returns everything. No native renderer yet (`MercantisCoreUI` has no `GenericReportView`). |
| Audit log | ✅ Ready | `AuditLogWriter` (Phase A §3.2, ADR-039) writes inside the same atomic block as save/applyRemote/delete, and follow-on rows for submit/cancel/amend lifecycle events. Reader API exposed via `DocumentEngine.auditEntries(forDocumentId:)` / `(forDocType:limit:offset:)`. |
| Files / Attachments | ✅ Ready | `Files/` subsystem (Phase C / P3.1, ADR-043). `AttachmentStore` (filesystem) + `AttachmentManager` (atomic metadata + audit). `DocumentEngine` cascade-on-delete via optional `attachmentManager:` init dependency. SHA-256 integrity check on every read. |
| Print / PDF | ✅ Ready | `Printing/` subsystem (Phase C / P3.2, ADR-044). Declarative `PrintFormat` + `LetterHead`, pluggable `PrintRenderer` per `PrintOutputKind`, plain-text and CoreGraphics PDF renderers, `PrintService` coordinator. UI-tier rich rendering remains a `MercantisCoreUI` follow-up. |
| ImportExport | ✅ Ready | `ImportExport/` subsystem (Phase C / P3.3, ADR-046). RFC-4180-ish `CSVCodec`, `DataExporter` (CSV + JSON), `DataImporter` routed through `DocumentEngine.save(...)` so validation / naming / audit / counter blocks all fire. Per-row outcome aggregation in `ImportReport`. |
| Notifications | ⚠️ Partial | Typed event bus ships and works. `NotificationLog` DocType, in-app inbox, email/SMS/webhook channels are not implemented. (Phase D) |
| Dashboards | ✅ Ready (engine) | `DashboardEngine` (Phase C / §3.10, ADR-045) resolves `DashboardDefinition` widgets into typed `DashboardResult` tiles using `DocumentEngine` + `ReportEngine`. Per-widget error isolation. SwiftUI `GenericDashboardView` is a `MercantisCoreUI` follow-up. |
| UIShell | ✅ Ready | `GenericFormView`, `GenericListView`, `NavigationShell`, `FormBuilderView`, link picker, inline child-table editor, rich text / image / barcode field types all ship. |
| SwiftPM split | ✅ Ready | `MercantisCore` (headless) + `MercantisCoreUI` (SwiftUI) means Hub can depend on the right surface cleanly. |

Legend: ✅ Ready · ⚠️ Partial · ❌ Missing

---

## 3. ERP-blocking gaps in detail

These are the gaps most likely to bite Hub as it builds out modules. Each
one has a concrete fix that lands inside an existing subsystem.

### 3.1 `DocumentEngine.list()` operator surface — ✅ shipped (Phase A, ADR-036)

`list(...)` now accepts `predicates: [ListFilter]?` alongside the legacy
`filters: [String: FieldValue]?` dictionary. Operators: `eq`, `neq`, `gt`,
`gte`, `lt`, `lte`, `between`, `in`, `like`, `isNull`, `isNotNull`. Predicates
push to SQL when the field is a system column or carries an
`IndexDefinition` (via `json_extract(payload, '$.<key>')`); everything else
falls back to a per-row in-memory evaluator with mirrored semantics. Sort,
limit, offset, and `whereExpression` continue to compose. See ADR-036.

### 3.2 Audit log writer + reader — ✅ shipped (Phase A, ADR-039)

`AuditLogWriter` writes inside the same atomic block as the document
mutation. Wired into save (`create`/`update`), `applyRemote`, `delete`,
and lifecycle follow-ons for `submit`/`cancel`/`amend`. Reader API exposed
via `DocumentEngine.auditEntries(forDocumentId:)` and
`auditEntries(forDocType:limit:offset:)`. The audit log is **not** subject
to ADR-028 sync-queue pruning.

### 3.3 `WorkflowTransitionHistory` auto-persistence — ✅ shipped (Phase A, ADR-038)

Migration v8 creates `workflow_transitions`. `WorkflowEngine` accepts an
optional `WorkflowTransitionHistoryWriter` (or a `database:` convenience
init) and calls `writer.append(history)` inside `transition(...)` after
the state update. Reader API exposed via the writer and via
`DocumentEngine.workflowTransitions(of:)` /
`workflowTransitions(forWorkflow:limit:offset:)`. Legacy "no writer =
return-only" behaviour is preserved.

### 3.4 `DocumentEngine.list` auto-applies `canAccessRow` — ✅ shipped (Phase A, ADR-037)

`DocType.rowAccessExpression: String?` declares the row-level security
predicate. `DocumentEngine.list(...)` evaluates it against
`PermissionEngine.canAccessRow(...)` for every fetched row using the
supplied (or defaulted) `userRoles`, `listUserId`, and `userAttributes`.
Per-call `applyRowAccess: false` opts out for maintenance / migration paths.

### 3.5 No real `CloudAdapter` implementation

**What ships today:** `CloudAdapter` protocol + `NoOpCloudAdapter`.

**Why it matters for ERP:** Multi-device, multi-user ERP requires a
real backend. Hub deployments will eventually need at least one
reference adapter (CloudKit, Supabase, S3+JSON, custom REST, etc.).

**Suggested fix:** Out of scope for Core itself per ADR-018 — Core
defines the protocol, host apps implement. But shipping at least one
reference adapter (likely CloudKit) would help Hub’s first
multi-device customer.

### 3.6 `DocumentNamingRule` conditional selector — ✅ shipped (Phase B, ADR-040)

`DocType.namingRules: [DocumentNamingRule]` declares priority-ordered
rules `(id, priority, condition, autoname)`. `NamingService.resolve(...)`
evaluates them in ascending priority; the first rule whose condition
matches wins, otherwise it falls through to `DocType.autoname`. A `nil`
or empty condition is a catch-all. Conditions that fail to evaluate
fail closed (skipped). Unblocks ERPnext-style per-company /
per-fiscal-year naming.

### 3.7 Naming counter range reservation — ✅ shipped (Phase B, ADR-042)

Migration v9 adds `naming_counter_blocks(seriesKey, deviceId, blockStart, blockEnd, nextValue)`.
`NamingCounterBlockReserver` allocates per-device blocks from the
shared `naming_counters` row, so two devices saving offline draw from
disjoint ranges and never pick the same `SINV-2026-0001`. Default
block size 50 keeps single-device behaviour byte-for-byte identical.
True cloud reconciliation (block invalidation on remote-higher-value)
is a `CloudAdapter` follow-up per ADR-018.

### 3.8 SchedulerService ↔ AutomationRunner wiring — ✅ shipped (Phase B, ADR-041)

`AutomationRule` gains an optional `schedule: ScheduleInterval?`.
`AutomationRunner` accepts an optional `scheduler:` at init; when
present, `register(rules:appId:)` registers a `ScheduledTask` per
`onSchedule` rule. On tick, the runner iterates documents of the
rule's `docType` (via the new `gateway.listDocuments(docType:)`),
evaluates the condition per document, and runs the actions on
matches. `unregister(appId:)` and `applyManifests(_:)` cancel old
handles cleanly.

### 3.9 Files / Print / Import-Export — ✅ shipped (Phase C, ADRs 043 / 044 / 046)

- **Files (P3.1, ADR-043):** `Files/` subsystem with `AttachmentStore`
  (bytes on disk under `<dbDir>/attachments/<documentId>/`),
  `AttachmentManager` (atomic metadata + audit), and `DocumentEngine`
  cascade-on-delete via the optional `attachmentManager:` init
  dependency. SHA-256 hashing on every write enables integrity
  verification on every read.
- **Print / PDF (P3.2, ADR-044):** `Printing/` subsystem with
  declarative `PrintFormat` + `LetterHead`, pluggable `PrintRenderer`
  per `PrintOutputKind`, plain-text and CoreGraphics PDF renderers,
  and a `PrintService` coordinator. UI-tier rich rendering remains a
  `MercantisCoreUI` follow-up.
- **Import / Export (P3.3, ADR-046):** `ImportExport/` subsystem with
  RFC-4180-ish `CSVCodec`, `DataExporter` (CSV + JSON envelope),
  and `DataImporter` routed through `DocumentEngine.save(...)` so the
  validation pipeline, naming service, audit log, and per-device
  counter blocks all fire identically to interactive saves. Per-row
  outcomes aggregate into `ImportReport`.

### 3.10 Dashboard runtime — ✅ shipped (Phase C, ADR-045)

`DashboardEngine` lives under `mercantis core/Reporting/`. It registers
`DashboardDefinition`s and resolves them into typed `DashboardResult`
trees (count / list / chart / shortcut tiles, plus an `error` case for
per-widget failure isolation). Counts and lists run through
`DocumentEngine.list(...)` (with `ListFilter` predicates parsed from
widget parameters); charts defer to `ReportEngine.execute(...)`.

The SwiftUI `GenericDashboardView` that consumes a `DashboardResult` is
a follow-up in `MercantisCoreUI`. The engine library contract — the
typed result — is shipped.

---

## 4. Suggested fix order

### Phase A — Engine fixes that unblock real list views — ✅ shipped 2026-05-05

1. ✅ **§3.1 `list()` operators + sort + push-to-SQL** — typed `ListFilter`
   surface (ADR-036). Every module benefits immediately.
2. ✅ **§3.4 Auto-apply `canAccessRow`** — `DocType.rowAccessExpression`
   (ADR-037), evaluated by `list()` for every row.
3. ✅ **§3.3 Persist `WorkflowTransitionHistory`** — migration v8 +
   `WorkflowTransitionHistoryWriter` (ADR-038).
4. ✅ **§3.2 Audit log writer + reader** — `AuditLogWriter` wired into the
   atomic write block (ADR-039).

### Phase B — Wiring and naming polish — ✅ shipped 2026-05-05

5. ✅ **§3.8 Scheduler ↔ AutomationRunner** (ADR-041). `onSchedule`
   automation rules now fire across every document of the rule's
   DocType, with per-document condition evaluation.
6. ✅ **§3.6 `DocumentNamingRule`** (ADR-040). Priority-ordered
   conditional selector evaluated in `NamingService.resolve(...)`.
7. ✅ **§3.7 Counter range reservation** (ADR-042). Per-device
   block allocation backed by migration v9's `naming_counter_blocks`.

### Phase C — ERP feature breadth — ✅ shipped 2026-05-05

8. ✅ **Files / Attachments (P3.1, ADR-043).** `Files/` subsystem
   with on-disk store, atomic metadata writes, audit-log integration,
   and `DocumentEngine` cascade-on-delete.
9. ✅ **Print / PDF (P3.2, ADR-044).** `Printing/` subsystem with
   declarative formats and plain-text + CoreGraphics PDF renderers.
10. ✅ **Dashboard runtime (§3.10, ADR-045).** `DashboardEngine`
    resolves widgets into typed result tiles. `MercantisCoreUI` view
    is a follow-up.
11. ✅ **Import / Export (P3.3, ADR-046).** CSV + JSON via
    `DataExporter` / `DataImporter` routed through
    `DocumentEngine.save(...)`.

### Phase D — Production readiness

12. **At least one real `CloudAdapter` implementation (§3.5).**
13. **`NotificationLog` + at least one channel** (in-app inbox or email).
14. **`ReportEngine` role filtering** + a `GenericReportView` in `MercantisCoreUI` (Hub Wall 9).

---

## 5. What Core does not need to do

- ERP _domain_ DocTypes (Customer, Item, Sales Invoice, GL Entry, …) live
  in Hub, not Core. ADR-001 / ADR-007 are the contract.
- The `MercantisCLI` install / patch flow already shares one pipeline with
  the in-app installer (P2.3); no further work needed here.
- The SwiftPM split (`MercantisCore` vs `MercantisCoreUI`) is already
  consumable from Hub; the Xcode app target migrating onto the SwiftPM
  libraries is a `.pbxproj` chore, not an architectural item.

---

# Implementation Status

_Last updated: 2026-04-29 (W9 — barcode / QR field type)_

A candid map between `ARCHITECTURE.md` / the ADR set and what is actually present in `mercantis core/`. Each entry is graded:

- **Shipped** — matches the documented contract, end-to-end.
- **Partial** — real implementation, but narrower than the doc claims (explicit caveats below).
- **Stub** — type/method exists but the moving parts don’t.
- **Planned** — accurately labelled as planned in the docs; absent from code, which is fine.
- **Missing** — the docs describe it as present, but nothing exists on disk.

---

## 1. Directory Structure: doc vs. reality

`ARCHITECTURE.md` §7 lists a directory tree. The on-disk tree differs:

| Directory in §7 | On disk? | Notes |
|---|---|---|
| `AppRuntime/` | Yes | Matches §4.9. |
| `Automation/` | **No** | Nothing on disk. ADR-025 / §4.13 describe `AutomationActionRegistry`, `AutomationActionHandler`, `BuiltInActionHandlers`. None exist. |
| `Cache/` | **No** | No `CacheManager.swift`. `MetaComposer` carries its own generation counter; there is no cross-subsystem cache. |
| `Customization/` | Yes (partial) | Contains `CustomField.swift`, `PropertySetter.swift`. `ClientScript.swift` (referenced in §4.19) is missing. |
| `DocumentEngine/` | Yes | Matches §4.2 / §4.10. |
| `ExpressionEngine/` | Yes | AST-based parser + interpreter. `referencedFields` static analysis wired into `SchemaValidator` (P2.1). |
| `Files/` | **No** | §4.18 describes `File.swift`, `FileManager.swift`. Neither exists. |
| `ImportExport/` | **No** | §4.20 describes `DataImporter.swift`, `DataExporter.swift`. Neither exists. |
| `Metadata/` | Yes | Matches §4.1. |
| `Naming/` | Yes | Ships `NamingStrategy`, `NamingContext`, `NamingError`, `NamingService`, `UUIDv7Strategy`, `NamingSeriesStrategy`, `FieldDerivedStrategy`, `PromptStrategy`, `FormatStrategy` (P1.1 / ADR-014, 2026-04-23). `DocumentNamingRule` conditional selector is still unimplemented. |
| `Notifications/` | Yes | Has **both** `EventBus.swift` (ADR-012, superseded) and `EventEmitter.swift` (ADR-020). `DocumentEngine` still requires an `EventBus` in its initializer, so the old path has not been retired. |
| `Permissions/` | Yes | `PermissionEngine.swift` is the only file and matches the revised §4.4 / ADR-011 (flat surface — see P0.5). `PermissionContext.swift` and `PermissionEvaluators.swift` were documented by earlier revisions but are no longer part of the target shape. |
| `Printing/` | **No** | `LetterHead.swift`, `PDFGenerator.swift`, `PrintFormat.swift` absent. (Docs correctly mark §4.17 _planned_, but §7’s tree still lists them.) |
| `Reporting/` | Yes | `ReportEngine.swift` only. |
| `Scheduling/` | Yes | Ships `ScheduledTask`, `CronExpression`, `SchedulerPersistence`, `SchedulerService` (P1.4 / §4.13, 2026-04-24). Cadence is persisted in the v6 `scheduler_state` table. |
| `Storage/` | Yes | Matches §4.3. |
| `SyncEngine/` | Yes | Also contains `CloudAdapter.swift` with a `NoOpCloudAdapter` — not listed in §7 but referenced elsewhere (ADR-018). |
| `UIShell/` | Yes (much larger than §7) | See §2.17 “UIShell reality” below. Now its own SwiftPM library product `MercantisCoreUI` (P2.7). |
| `Workflows/` | Yes | Matches §4.5. |
| `Views/DesignSystem/` | **On disk, not in §7** | 14 files of demo/design-lab surfaces. Mentioned in prose in §5.1 but not in the tree. |

### ADR index drift

- `Docs/ADR/ADR-027-doctype-creation-strategy.md` is listed in `Docs/ADR/README.md` but was missing from `ARCHITECTURE.md` §8. Fixed in this changeset.

---

## 2. Subsystem-by-subsystem grading

### 2.1 Metadata Engine — §4.1

- **Shipped** — `DocType`, `FieldDefinition`, `PermissionRule`, `SyncPolicy`, `IndexDefinition`, `SchemaValidator`, `MetadataRegistry`.
- **Shipped** — `MetaComposer` + `ResolvedMeta` (ADR-021). Composition merges base → custom fields → property setters with a working cache invalidation generation counter.
- **Partial** — `SchemaValidator` exists (68 lines) but the set of rules it enforces is narrow; verifying this against ADR-003 is worth a pass.

### 2.2 Document Engine — §4.2 / §4.10

- **Shipped** — `save`, `delete`, `fetch`, `list`, `submit`, `cancel`, `amend`. Mutation-log writes are atomic with the document row (single GRDB `write { db in … }`).
- **Shipped** — Optimistic concurrency via `updatedAt` comparison (ADR-023).
- **Shipped** — Submit-time immutability gate with `allowOnSubmit` (ADR-013); cancel refuses when linked submitted documents reference the doc.
- **Shipped** — Field-level diffs written to `document_versions` on save (ADR-024).
- **Shipped** — `ValidationPipeline` protocol + stages (ADR-022): type coercion, required, link, unique, expression rule, workflow guard, permission. All seven are real guards composed in `DocumentEngine.save` (and `applyRemote`). `WorkflowGuardStage` enforces declared transitions, roles, and condition expressions against the persisted `status`; `PermissionStage` delegates to `PermissionEngine.canPerform`. (P1.5 — 2026-04-23)
- **Partial** — `list(docType:filters:)` filters are equality-only. No sort, no limit, no LIKE/range, despite `§4.15` advertising `sortBy:limit:`.
- **Partial** — `audit_log` table is created in the migration but nothing writes to it. §4.3 describes it as “the immutable audit trail of all document mutations”; in practice the sync queue is acting as that log.

### 2.3 Storage — §4.3

- **Shipped** — `MercantisDatabase`, `MigrationRunner`. Six versioned migrations: **v1** creates the advertised tables (`doctypes`, `fields`, `documents`, `document_children`, `sync_queue`, `audit_log`, `apps`, `workflows`); **v2** adds `docStatus` + `amendedFrom` columns (ADR-013); **v3** adds `document_versions` (ADR-024); **v4** adds the `sync_state` key/value table (P0.3 bookmark persistence); **v5** adds `naming_counters` for sequential series IDs (P1.1 / ADR-014); **v6** adds `scheduler_state(taskKey, lastRunAt)` so `SchedulerService` can survive process restarts (P1.4).
- **Partial** — Migrations are forward-only (as intended) but there is no test suite asserting schema shape.
- **Partial** — `audit_log` has neither a writer nor a reader API. Created, never used.

### 2.4 Permissions Engine — §4.4

- **Shipped** — `PermissionEngine` exposes `canPerform(operation:on:userRoles:)`, `canAccessField(fieldKey:on:userRoles:operation:)`, and `canAccessRow(document:userRoles:rowExpression:userId:userAttributes:expressionEvaluator:)`. `ValidationPipeline`’s `PermissionStage` calls into `canPerform`.
- **Aligned (P0.5 — 2026-04-23)** — §4.4 and ADR-011 now describe the flat method surface that actually ships.
- **Shipped (P1.7 — 2026-04-25)** — `canAccessRow` now evaluates a sandboxed boolean `rowExpression` via `ExpressionEvaluator` over the document’s fields plus a `user.*` namespace. A `nil`/empty expression grants access; an expression that throws fails closed. Coverage in `PermissionEngineTests.swift`.
- **Not implemented** — There is no app-/module-level gate. Workflow transition role checks live inside `WorkflowEngine.availableTransitions` and are not routed through `PermissionEngine`. `DocumentEngine.list` does not yet apply `canAccessRow` automatically.

### 2.5 Workflow Engine — §4.5

- **Shipped** — `availableTransitions`, `transition`, transition-history records, event emission.
- **Partial** — `WorkflowTransitionHistory` is produced and returned to the caller but is **not persisted** anywhere in `WorkflowEngine`; it’s up to the caller to store it. §4.5 implies it’s recorded automatically.

### 2.6 Sync Engine — §4.6 / ADR-005 / ADR-006

- **Shipped** — Push of pending mutations, pull of remote mutations, per-DocType sync-policy lookup, `ConflictResolver` with LWW / VCM / AO.
- **Shipped** — `CloudAdapter` protocol + `NoOpCloudAdapter`.
- **Shipped (P0.2)** — Remote upserts are now routed through `DocumentEngine.applyRemote(_:from:)`, so `ValidationPipeline`, submit-immutability guard, and `DocumentVersion` diff recording all fire on sync-received writes.
- **Shipped (P0.3)** — `lastServerSequence` now persists in a v4 `sync_state` key/value table.
- **Shipped (P0.4 / ADR-028)** — `SyncEngine.pruneSyncQueue(force:)` deletes acknowledged `.pushed` and `.applied` rows once they fall outside the retention window (default 30 days each).
- **Shipped (W6, 2026-04-29)** — typed `FieldValue` coercion + round-trip: `DocumentEngine.save` / `fetch` preserve the tagged JSON envelope for `.date`, `.dateTime`, `.data`, and `.array`.
- **Partial** — `resolveConflict(docType:documentId:chosenVersion:resolvedBy:)` appends a `resolveConflict` mutation but does not load the chosen version’s payload.

### 2.7 Expression Engine — §4.7 / ADR-017

- **Shipped (P2.1, 2026-04-25)** — The evaluator is now a two-phase design: `ExpressionParser` builds a typed `ExpressionNode` AST (`.literal`, `.fieldRef`, `.unary`, `.binary`, `.call`) and `ExpressionEvaluator` walks it. Every node carries a UTF-8 `[start, end)` source range. New public APIs: `parse(_:)`, `evaluateBool(parsed:context:)`, `evaluateFormula(parsed:context:)`, `referencedFields(in:)`. A bounded LRU caches recently-parsed source strings (configurable `parseCacheLimit`, default 256). `SchemaValidator.validate(_:)` calls `referencedFields` on every field-level `visibilityExpression` / `readOnlyExpression` / `formulaExpression` and rejects DocTypes whose expressions reference an undeclared field key.
- **Shipped (P0.9, 2026-04-22)** — Unary minus mid-expression parses correctly through the new AST grammar.
- **Shipped (P1.6, 2026-04-24)** — `FieldValue` now includes `.date(Date)`, `.dateTime(Date)`, `.data(Data)`, and `.array([FieldValue])` with a tagged-envelope wire format.
- **Shipped (P2.2 / ADR-029, 2026-04-25)** — Cross-document `lookup("DocType", id, "field")` recognised by the evaluator when constructed with a `DocumentLookupResolver`. A per-evaluation `lookupBudget` (default 32) caps cross-document reads.
- **Partial** — Workflow `transition.conditionExpression` and `AutomationRule.conditionExpression` are not yet validated at install time.

### 2.8 Notifications & Events — §4.8 / ADR-020

- **Shipped** — `EventEmitter`, `MercantisEvent` marker protocol, concrete event types (`DocumentSavedEvent`, `DocumentDeletedEvent`, `DocumentSubmittedEvent`, `DocumentCancelledEvent`, `DocumentAmendedEvent`, `WorkflowTransitionEvent`, `AppInstalledEvent`). `EventBus.swift` / `EventEmitter(legacyBus:)` removed (P0.6).
- **Missing** — In-app `NotificationLog` DocType, notification rules, email/SMS/webhook channels described in §4.16.

### 2.9 App Runtime — §4.9 / §4.12

- **Shipped** — `AppManifest` (Codable), `AppInstaller.install(_:)`, `AppInstaller.uninstall(appId:)`, `installApp` mutation flow.
- **Shipped (P1.3, 2026-04-24)** — `AppManifest.extensionPoints: ExtensionPoints`, `ExtensionPointResolver` binds `documentEventSubscription` declarations to the typed `EventEmitter` and forwards `schedulerEvent` declarations to an `ExtensionSchedulerRegistrar`. `AppInstaller.install` / `uninstall` now call the resolver; `AppInstaller.restoreExtensionPoints()` rebinds on launch.
- **Missing** — The main app (`mercantis_coreApp.swift`) does not yet construct an `AppInstaller` or call `restoreExtensionPoints()` at launch.

### 2.10 Document Lifecycle — §4.10 / ADR-013

- **Shipped** — Submit / Cancel / Amend flow with correct docStatus transitions and the cancel link-integrity guard.
- **Partial** — `amend` creates a new Draft with `amendedFrom` set. Amendment audit lineage is captured, but not surfaced in `DocumentVersion`.

### 2.11 Naming System — §4.11 / ADR-014

- **Shipped (P1.1, 2026-04-23)** — `NamingStrategy` protocol, `NamingContext`, `NamingError`, `NamingService` registry, and five built-in strategies: `UUIDv7Strategy` (default, RFC 9562), `NamingSeriesStrategy` (e.g. `SINV-.YYYY.-.####` with date-token expansion and `naming_counters`-backed counters), `FieldDerivedStrategy` (`field:email`), `PromptStrategy` (`prompt`, requires caller-supplied name), `FormatStrategy` (`format:{customer}-{year}`). `DocumentEngine.save` resolves empty `Document.id` before validation. Counter reservation runs in its own short write transaction, so a validation-or-write failure after reservation leaves a gap in the sequence — the standard ERP behaviour, documented in ADR-014.
- **Missing** — `DocumentNamingRule` conditional selector (priority-ordered rules that pick different strategies based on field values).
- **Known limitation** — Naming counters are currently local-only: offline multi-device usage is not yet reconciled through the sync queue (ADR-014 calls out per-device range reservation as the fix, but it is not implemented).

### 2.12 Scheduling & Automation — §4.13 / ADR-019 / ADR-025

- **Shipped (Automation, P1.2 — 2026-04-24)** — Action registry + built-in handlers wired through `ExtensionActionDispatcher`. Covered in `AutomationTests.swift`.
- **Shipped (Scheduling, P1.4 — 2026-04-24)** — `mercantis core/Scheduling/` ships `ScheduledTask`, `CronExpression`, `SchedulerPersistence`, and `SchedulerService`. `SchedulerService` conforms to `ExtensionSchedulerRegistrar`. Last-run state survives process restarts via the v6 `scheduler_state` table. `AppInstaller.uninstall` calls `SchedulerService.unregister(appId:)` to wipe persisted state on full uninstall.
- **Cron support** — dependency-free five-field parser (minute, hour, day-of-month, month, day-of-week). Supports `*`, integer, comma-separated lists, inclusive ranges, and `*/step`. Day-of-week accepts `0`–7 with both `0` and `7` binding to Sunday. `@yearly` / `@daily` aliases are not supported — `ScheduleInterval` already covers those cases.
- **Known follow-ups** — `mercantis_coreApp.swift` still does not construct an `AppInstaller` / `SchedulerService` at launch. Scheduler-triggered automation rules (`triggerEvent == "onSchedule"`) are still no-ops because the runner is not wired to the scheduler.

### 2.13 Caching Layer — §4.14

- **Partial.** `MetaComposer` has a per-key generation-counter cache. `MetadataRegistry` has a dictionary populated at install time. There is no `CacheManager`, no query-result cache, no document cache, and no global invalidation mechanism that other subsystems can trigger.

### 2.14 Public API Surface — §4.15

- **Shipped** — Everything listed in the “Key API points” bullets exists with the signatures shown, **except**:
  - `PermissionEngine.canPerform(operation:on:context:)` — real signature is `canPerform(operation:on:userRoles:)`. No `context:` parameter.
  - `DocumentEngine.list(docType:filters:sortBy:limit:)` — real signature is `list(docType:filters:)` only.
  - `AutomationActionRegistry` — does not exist.

### 2.15 Files / Import-Export / Printing — §§4.17–4.20

- **Missing** — Files, Printing, Import/Export not implemented. §4.17 is correctly labelled _planned_; §4.18 and §4.20 are not, but should be.

### 2.16 Realtime Updates — §4.21

- **Shipped** — Event emission via `EventEmitter` gives SwiftUI refresh points.
- **Planned** — WebSocket adapter is correctly labelled planned.

### 2.17 UI Shell — §5.1

- **Shipped** — `NavigationShell`, `CommandBarView`, `GenericFormView`, `GenericListView`, `FormBuilderView`, `DocTypeBuilderView`, `DocTypeListView`. Three-pane FormBuilder with dedicated `WindowGroup` works.
- **Note** — UIShell is by far the largest subsystem. The core engine (DocumentEngine + SyncEngine + ExpressionEngine) totals ~1,850 lines. The balance of effort is ~60% UI, ~20% engine, ~20% everything else.
- **Partial** — `AppManifest.dashboards: [DashboardDefinition]` decodes into the manifest, but there is no `DashboardView` or dashboard rendering code. The type exists; the runtime does not.
- **Footgun** — `DocTypeBuilderView.swift` does `fatalError` when the metadata DB won’t open. Acceptable for a builder surface, but it’s the only `fatalError` in the codebase.
- **Link picker (W4 / ADR-030, 2026-04-29)** — `LinkPickerField` view added to `MercantisCoreUI`. `GenericFormView` accepts an optional `linkSearchProvider: ((String, String) -> [Document])?` closure; when supplied the form renders a search-as-you-type picker sheet for `FieldType.link` fields. When `nil` (the default), the form falls back to plain `TextField` — fully backwards-compatible.
- **Inline child-table editor (W5 / ADR-031, 2026-04-29)** — `ChildTableField` view added to `MercantisCoreUI`. `GenericFormView` accepts an optional `childDocTypeProvider: ((String) -> DocType?)?` closure; when supplied the form renders an editable inline grid for `FieldType.table` fields, with columns derived from the child DocType’s field schema. Children persist atomically through the existing `Document.children` / `ChildRow` plumbing.
- **Rich text field (W7 / ADR-033, 2026-04-29)** — `FieldType.richText` persists Markdown as a plain `String`. `RichTextField` adds an edit/preview toggle backed by `AttributedString(markdown:)`. `GenericListView` strips Markdown to a single-line plain-text summary.
- **Image field (W8 / ADR-034, 2026-04-29)** — `FieldType.image` persists as `.data(...)` (with legacy `.string(...)` URLs still accepted by validation). `ImageField` adds an inline thumbnail preview plus a native chooser (`PhotosPicker` on iOS, `NSOpenPanel` on macOS).
- **Barcode field (W9 / ADR-035, 2026-04-29)** — `FieldType.barcode` persists as a plain `String`. `BarcodeField` adds a text field plus an iOS-only `AVFoundation` scan button/sheet; on macOS the scan button is hidden and manual entry remains available.

#### Metadata workspace UX contract (shipped 2026-04-23)

| Component | Role |
|---|---|
| `MercantisSectionHeading` | Structural section headers — uppercase tracking text, no background fill. Clearly non-interactive. |
| `SelectedRecordHeader` | Workspace entity banner — surface background, bottom divider, title + subtitle + badge row. Used in Module and DocType detail views. |
| `RecordCollectionHostView` + `RecordWorkspaceToolbarContent` | Shared workspace chrome for all metadata record collections. |
| `DocTypeBuilderView` | Restructured into three groups: Basic Info / Schema (tabbed: Fields, Permissions) / Configuration (Sync + Indexes). Collections use compact list rows with inline expand-on-select editors. |

### 2.18 Reporting — §5.2

- **Partial** — `ReportEngine.register`, `availableReports`, `execute`. `availableReports(for:)` ignores its argument and returns all reports today.

### 2.19 Cloud Adapter — §5.3

- **Shipped** — Protocol defined (ADR-018) with a `NoOpCloudAdapter` default. Correctly labelled planned at the implementation level (no concrete backend).

---

## 3. Test coverage

- **XCTest tests written in `mercantis coreTests/`.** Covers `ExpressionEvaluator`, `MetaComposer`, `ConflictResolver`, `ValidationPipeline`, `DocumentEngine` (save/fetch/concurrency/submit/cancel/amend), `MigrationRunner` (v1–v6 + idempotency), `Naming`, `Automation`, `ExtensionPoints`, and `Scheduler` (cron parser, persistence, due-check, `ExtensionSchedulerRegistrar` conformance, end-to-end through `AppInstaller`).
- **Wire-up pending.** The test target does not yet exist in `project.pbxproj`. `mercantis coreTests/README.md` lists the one-time Xcode setup. After that, `⌘U` or `xcodebuild test` runs the suite.

---

## 4. SwiftPM products

`Package.swift` declares three products:

- `.library(name: "MercantisCore", targets: ["MercantisCore"])` — the engine, importable via `.package(url:from:)`. The target points at `mercantis core/` with `exclude: ["Assets.xcassets", "mercantis_coreApp.swift", "UIShell", "Views"]`, so SwiftUI / app-shell code is deliberately not part of the library. GRDB (`https://github.com/groue/GRDB.swift`, `from: "6.0.0"`) is declared on the library target. Shipped in P2.6 (2026-04-25).
- `.library(name: "MercantisCoreUI", targets: ["MercantisCoreUI"])` — the SwiftUI shell. The target points at `mercantis core/UIShell/` and depends on `MercantisCore` + GRDB. Ships `GenericFormView`, `GenericListView`, `NavigationShell`, `DocTypeBuilderView`, `FormBuilderView`, `CommandBarView`, `RecordCollectionHostView`, and supporting view types as the public renderer surface. Hub and any third-party app that wants the out-of-the-box metadata-driven UI imports this product; headless consumers stick with `MercantisCore`. Shipped in P2.7 (2026-04-27).
- `.executable(name: "mercantis", targets: ["mercantis"])` — the CLI. Depends on `MercantisCore` (P2.3) for `install-app` / `list-apps` / `new-app` / `new-doctype`, and intentionally does **not** depend on `MercantisCoreUI`, so SwiftUI stays out of the CLI’s transitive graph.

---

## 5. The MercantisCLI target

`MercantisCLI/` is a separate SwiftPM executable built on `swift-argument-parser`. Commands:

- `new-app` — scaffold a canonical `AppManifest` JSON.
- `new-doctype` — scaffold a canonical `DocType` (encoded via Core’s `Codable`), optionally appending to a manifest.
- `install-app` — calls `AppInstaller.install(manifestData:)` against a `MercantisDatabase`. Same schema, same `SchemaValidator` pass, same side-effects as the in-app install path. Pre-decode envelope checks (reverse-DNS id, semver versions) run on the CLI side as a fast-fail layer. (P2.3)
- `migrate`, `create-patch`, `run-patch` — data-patch flow. These operate on `patch_log` and arbitrary SQL deltas rather than the engine schema.
- `list-apps` — reads the canonical `apps(id, name, version, installedAt, payload)` schema via `MercantisDatabase`.

---

## 6. Summary for new contributors

If you open the repo today expecting to find everything ARCHITECTURE.md §7 advertises, here is the short list of what _to stop looking for_:

- `Cache/`, `Files/`, `ImportExport/`, `Printing/` — do not exist. (`Naming/` shipped P1.1 — see §2.11; `Automation/` shipped P1.2; `Scheduling/` shipped P1.4 — see §2.12.)
- A chain-style `PermissionEvaluator` protocol — does not exist; `PermissionEngine` is a flat class, and §4.4 / ADR-011 now describe it as such (P0.5).
- Role-filtered `availableReports` — does not exist; returns all.
- Any XCTest target — does not exist.

Everything else in the doc is at least partially real. The _engine_ is in good shape; what remains is host-app wiring (constructing `AppInstaller` / `SchedulerService` at launch) and the `Files` / `Printing` / `ImportExport` subsystems. Naming shipped in P1.1 (§2.11); extension-point resolution shipped in P1.3 (§2.9); the automation runtime shipped in P1.2 (§2.12); the periodic-task scheduler shipped in P1.4 (§2.12).

---

## Cross-references

- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — full Core architecture.
- [`Docs/ADR/`](ADR/) — architecture decision records.
- [`Docs/ROADMAP.md`](ROADMAP.md) — enhancement backlog (P0–P3 items, sequencing, what not to build).
- [`Docs/UX-DIRECTION.md`](UX-DIRECTION.md) — UX direction, design strategy, macOS best practice guardrails, and `MercantisCoreUI` component roadmap.
- [`Docs/Examples/`](Examples/) — example manifests and porting guides.
- [`Docs/ARCHITECTURE-CHANGELOG.md`](ARCHITECTURE-CHANGELOG.md) — chronological record of architecture revisions.
- Hub-side: [`mercantis.hub.app/Docs/HUB-STATUS.md`](https://github.com/KevinBusuttil/mercantis.hub.app/blob/main/Docs/HUB-STATUS.md) — Hub implementation status and ERP module scorecard.
