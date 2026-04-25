# Implementation Status

_Last updated: 2026-04-25 (P2.6 — MercantisCore library product shipped)_

A candid map between `ARCHITECTURE.md` / the ADR set and what is actually present in `mercantis core/`. Each entry is graded:

- **Shipped** — matches the documented contract, end-to-end.
- **Partial** — real implementation, but narrower than the doc claims (explicit caveats below).
- **Stub** — type/method exists but the moving parts don't.
- **Planned** — accurately labelled as planned in the docs; absent from code, which is fine.
- **Missing** — the docs describe it as present, but nothing exists on disk.

The goal is not to assign blame; it's to give future contributors an honest starting map so they stop looking for files that don't exist, and so `ARCHITECTURE.md` can be tightened.

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
| `Printing/` | **No** | `LetterHead.swift`, `PDFGenerator.swift`, `PrintFormat.swift` absent. (Docs correctly mark §4.17 _planned_, but §7's tree still lists them.) |
| `Reporting/` | Yes | `ReportEngine.swift` only. |
| `Scheduling/` | Yes | Ships `ScheduledTask`, `CronExpression`, `SchedulerPersistence`, `SchedulerService` (P1.4 / §4.13, 2026-04-24). `SchedulerService` conforms to `ExtensionSchedulerRegistrar` so manifest-declared `schedulerEvents` are registered through `ExtensionPointResolver` exactly like document-event subscriptions. Cadence is persisted in the v6 `scheduler_state` table. |
| `Storage/` | Yes | Matches §4.3. |
| `SyncEngine/` | Yes | Also contains `CloudAdapter.swift` with a `NoOpCloudAdapter` — not listed in §7 but referenced elsewhere (ADR-018). |
| `UIShell/` | Yes (much larger than §7) | See §4 "UIShell reality" below. |
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
- **Partial** — `audit_log` table is created in the migration but nothing writes to it. §4.3 describes it as "the immutable audit trail of all document mutations"; in practice the sync queue is acting as that log.

### 2.3 Storage — §4.3

- **Shipped** — `MercantisDatabase`, `MigrationRunner`. Six versioned migrations: **v1** creates the advertised tables (`doctypes`, `fields`, `documents`, `document_children`, `sync_queue`, `audit_log`, `apps`, `workflows`); **v2** adds `docStatus` + `amendedFrom` columns (ADR-013); **v3** adds `document_versions` (ADR-024); **v4** adds the `sync_state` key/value table (P0.3 bookmark persistence); **v5** adds `naming_counters` for sequential series IDs (P1.1 / ADR-014); **v6** adds `scheduler_state(taskKey, lastRunAt)` so `SchedulerService` can survive process restarts (P1.4).
- **Partial** — Migrations are forward-only (as intended) but there is no test suite asserting schema shape.
- **Partial** — `audit_log` has neither a writer nor a reader API. Created, never used.

### 2.4 Permissions Engine — §4.4

- **Shipped** — `PermissionEngine` exposes `canPerform(operation:on:userRoles:)`, `canAccessField(fieldKey:on:userRoles:operation:)`, and `canAccessRow(document:userRoles:rowExpression:userId:userAttributes:expressionEvaluator:)`. `ValidationPipeline`'s `PermissionStage` calls into `canPerform`.
- **Aligned (P0.5 — 2026-04-23)** — §4.4 and ADR-011 now describe the flat method surface that actually ships. The earlier `PermissionEvaluator` / `PermissionDecision` evaluator-chain wording was removed from §4.4, ADR-011, ADR-025, and ADR-026.
- **Shipped (P1.7 — 2026-04-25)** — `canAccessRow` now evaluates a sandboxed boolean `rowExpression` via `ExpressionEvaluator` over the document's fields plus a `user.*` namespace (`user.id`, `user.roles`, plus arbitrary caller-supplied `userAttributes`). The previous equality-only dictionary filter was replaced (no callers existed). A `nil`/empty expression grants access; an expression that throws fails closed. Coverage in `PermissionEngineTests.swift`.
- **Not implemented** — There is no app-/module-level gate (nothing checks "is this role allowed to use this module at all?"). Workflow transition role checks live inside `WorkflowEngine.availableTransitions` and are not routed through `PermissionEngine`. `DocumentEngine.list` does not yet apply `canAccessRow` automatically — callers must pass the row expression themselves.

### 2.5 Workflow Engine — §4.5

- **Shipped** — `availableTransitions`, `transition`, transition-history records, event emission.
- **Partial** — `WorkflowTransitionHistory` is produced and returned to the caller but is **not persisted** anywhere in `WorkflowEngine`; it's up to the caller to store it. §4.5 implies it's recorded automatically.

### 2.6 Sync Engine — §4.6 / ADR-005 / ADR-006

- **Shipped** — Push of pending mutations, pull of remote mutations, per-DocType sync-policy lookup, `ConflictResolver` with LWW / VCM / AO.
- **Shipped** — `CloudAdapter` protocol + `NoOpCloudAdapter`.
- **Shipped (P0.2)** — Remote upserts are now routed through `DocumentEngine.applyRemote(_:from:)`, so `ValidationPipeline`, submit-immutability guard, and `DocumentVersion` diff recording all fire on sync-received writes. `UpsertPayload` has been replaced by encoding the full `Document` into the mutation, so push carries a round-trippable payload.
- **Shipped (P0.3)** — `lastServerSequence` now persists in a v4 `sync_state` key/value table. `SyncEngine` loads the bookmark at init and writes it back on every advance, so a process restart no longer re-pulls already-applied remote mutations.
- **Shipped (P0.4 / ADR-028)** — `SyncEngine.pruneSyncQueue(force:)` deletes acknowledged `.pushed` and `.applied` rows once they fall outside the retention window (default 30 days each). `.pending` and `.conflicted` rows are retained indefinitely. Pruning is throttled by a persisted `syncQueuePrunedAt` watermark in `sync_state` (default 24h) and is invoked opportunistically at the end of `pushPendingMutations()` / `pullAndApplyRemoteMutations()`.
- **Partial** — `resolveConflict(docType:documentId:chosenVersion:resolvedBy:)` appends a `resolveConflict` mutation but does not load the chosen version's payload — the document row is left as whatever the last write set it to.

### 2.7 Expression Engine — §4.7 / ADR-017

- **Shipped (P2.1, 2026-04-25)** — The evaluator is now a two-phase design: `ExpressionParser` builds a typed `ExpressionNode` AST (`.literal`, `.fieldRef`, `.unary`, `.binary`, `.call`) and `ExpressionEvaluator` walks it. Every node carries a UTF-8 `[start, end)` source range; parse errors lift through `EvaluatorError.parseError(ExpressionParseError)` whose `description` renders the source line and a `^` caret. New public APIs: `parse(_:)`, `evaluateBool(parsed:context:)`, `evaluateFormula(parsed:context:)`, `referencedFields(in:)`. A bounded LRU caches recently-parsed source strings (configurable `parseCacheLimit`, default 256). Pure-literal subtrees collapse at parse time (constant folding); subtrees that throw at fold time (e.g. `10 / 0`) are deliberately left unfolded so the runtime error contract holds. `SchemaValidator.validate(_:)` calls `referencedFields` on every field-level `visibilityExpression` / `readOnlyExpression` / `formulaExpression` and rejects DocTypes whose expressions reference an undeclared field key — two new `ValidationError` cases, `unknownFieldInExpression` and `expressionParseFailed`, surface this at install time. The existing public API (`evaluateBool(expression:context:)`, `evaluateFormula(expression:context:)`, the four `EvaluatorError` cases) is preserved verbatim.
- **Shipped (P0.9, 2026-04-22)** — Unary minus mid-expression (`1 + -2`, `-price`, `-(a + b)`) parses correctly through the new AST grammar — unary `-` / `+` / `!` bind tighter than every binary operator.
- **Shipped (P1.6, 2026-04-24)** — `FieldValue` now includes `.date(Date)`, `.dateTime(Date)`, `.data(Data)`, and `.array([FieldValue])`. The four new cases encode as a tagged envelope (`{"$type": "date|datetime|data|array", "$value": ...}`) so they round-trip distinctly; the legacy primitives (`.string` / `.int` / `.double` / `.bool` / `.null`) still encode as untagged JSON and existing payloads continue to decode. Downstream wiring updated: `TypeCoercionStage` accepts typed dates for `.date` / `.datetime` fields and `.data` for `.attachment`; `RequiredFieldStage` treats typed dates as always non-empty and an empty `.data` / `.array` as empty; `ExpressionEvaluator` compares dates as epoch seconds; `GenericFormView.dateBinding` writes typed `.date` / `.dateTime` on save.
- **Partial** — No `lookup(docType, name, field)` (P2.2). The `.call` AST node is parsed but rejected by the interpreter so the AST shape is forward-compatible with `lookup()` when it lands.
- **Partial** — Workflow `transition.conditionExpression` and `AutomationRule.conditionExpression` are not yet validated at install time. Both reference DocType fields and would benefit from the same `referencedFields` check; the wire-up belongs in `AppInstaller.install` rather than `SchemaValidator` (the rules don't live on the DocType). Filed for a future pass.

### 2.8 Notifications & Events — §4.8 / ADR-020

- **Shipped** — `EventEmitter`, `MercantisEvent` marker protocol, concrete event types (`DocumentSavedEvent`, `DocumentDeletedEvent`, `DocumentSubmittedEvent`, `DocumentCancelledEvent`, `DocumentAmendedEvent`, `WorkflowTransitionEvent`, `AppInstalledEvent`). `EventBus.swift` / `EventEmitter(legacyBus:)` removed (P0.6).
- **Missing** — In-app `NotificationLog` DocType, notification rules, email/SMS/webhook channels described in §4.16. §4.16 itself says "in progress".

### 2.9 App Runtime — §4.9 / §4.12

- **Shipped** — `AppManifest` (Codable), `AppInstaller.install(_:)`, `AppInstaller.uninstall(appId:)`, `installApp` mutation flow.
- **Shipped (P1.3, 2026-04-24)** — `AppManifest.extensionPoints: ExtensionPoints`, `ExtensionPointResolver` binds `documentEventSubscription` declarations to the typed `EventEmitter` and forwards `schedulerEvent` declarations to an `ExtensionSchedulerRegistrar`. `AppInstaller.install` / `uninstall` now call the resolver; `AppInstaller.restoreExtensionPoints()` rebinds on launch. Action dispatch routes through the `ExtensionActionDispatcher` seam that P1.2's `AutomationActionRegistry` will conform to; the default `LoggingExtensionActionDispatcher` records dispatches for test assertions until then.
- **Missing** — The main app (`mercantis_coreApp.swift`) does not yet construct an `AppInstaller` or call `restoreExtensionPoints()` at launch. The real action dispatcher (P1.2) and real scheduler registrar (P1.4) both ship and are ready to wire — Hub / app-shell integration is the consumer.

### 2.10 Document Lifecycle — §4.10 / ADR-013

- **Shipped** — Submit / Cancel / Amend flow with correct docStatus transitions and the cancel link-integrity guard.
- **Partial** — `amend` creates a new Draft with `amendedFrom` set (verified in DocumentEngine). Amendment audit lineage is captured, but not surfaced in `DocumentVersion`.

### 2.11 Naming System — §4.11 / ADR-014

- **Shipped (P1.1, 2026-04-23)** — `NamingStrategy` protocol, `NamingContext`, `NamingError`, `NamingService` registry, and five built-in strategies: `UUIDv7Strategy` (default, RFC 9562), `NamingSeriesStrategy` (e.g. `SINV-.YYYY.-.####` with date-token expansion and `naming_counters`-backed counters), `FieldDerivedStrategy` (`field:email`), `PromptStrategy` (`prompt`, requires caller-supplied name), `FormatStrategy` (`format:{customer}-{year}`). `DocumentEngine.save` resolves empty `Document.id` before validation; the resolved document is returned to the caller. Counter storage is a new `naming_counters(seriesKey, value)` table in migration v5. Counter reservation runs in its own short write transaction, so a validation-or-write failure after reservation leaves a gap in the sequence — the standard ERP behaviour, documented in `NamingSeriesStrategy` and ADR-014.
- **Missing** — `DocumentNamingRule` conditional selector (priority-ordered rules that pick different strategies based on field values).
- **Known limitation** — Naming counters are currently local-only: offline multi-device usage is not yet reconciled through the sync queue (ADR-014 calls out per-device range reservation as the fix, but it is not implemented).

### 2.12 Scheduling & Automation — §4.13 / ADR-019 / ADR-025

- **Shipped (Automation, P1.2 — 2026-04-24)** — see §2.9 for the runner / registry wiring; covered separately in `AutomationTests.swift`.
- **Shipped (Scheduling, P1.4 — 2026-04-24)** — `mercantis core/Scheduling/` ships `ScheduledTask`, `CronExpression`, `SchedulerPersistence`, and `SchedulerService`. `SchedulerService` conforms to `ExtensionSchedulerRegistrar`, so `ExtensionPointResolver` registers manifest-declared `schedulerEvents` against the real service rather than the recording stub. Last-run state survives process restarts via the v6 `scheduler_state` table. `AppInstaller.uninstall` calls `SchedulerService.unregister(appId:)` to wipe persisted state on full uninstall; reinstall preserves cadence.
- **Cron support** — dependency-free five-field parser (minute, hour, day-of-month, month, day-of-week). Supports `*`, integer, comma-separated lists, inclusive ranges, and `*/step`. Day-of-week accepts `0`–`7` with both `0` and `7` binding to Sunday. When both day fields are explicit, the matcher uses Vixie union semantics (DOM OR DOW). `@yearly` / `@daily` aliases are not supported — `ScheduleInterval` already covers those cases.
- **Known follow-ups** — `mercantis_coreApp.swift` still does not construct an `AppInstaller` / `SchedulerService` at launch; the host app / Hub will own that wiring. Scheduler-triggered automation rules (`triggerEvent == "onSchedule"`) are still no-ops because the runner is not wired to the scheduler. Background-task budget categories (`short` / `default` / `long` from §4.13) and `audit_log` writes for failed scheduled runs are not yet implemented.

### 2.13 Caching Layer — §4.14

- **Partial.** `MetaComposer` has a per-key generation-counter cache. `MetadataRegistry` has a dictionary that is populated at install time and on explicit `register(_:)`. There is no `CacheManager`, no query-result cache, no document cache, and no global invalidation mechanism that other subsystems can trigger.

### 2.14 Public API Surface — §4.15

- **Shipped** — Everything listed in the "Key API points" bullets exists with the signatures shown, **except**:
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
- **Footgun** — `DocTypeBuilderView.swift` does `fatalError` when the metadata DB won't open. Acceptable for a builder surface, but it's the only `fatalError` in the codebase.

#### Metadata workspace UX contract (shipped 2026-04-23)

`Modules`, `DocTypes`, and builder surfaces now share a consistent metadata-workspace UX language:

| Component | Role |
|---|---|
| `MercantisSectionHeading` | Structural section headers — uppercase tracking text, no background fill. Clearly non-interactive. |
| `SelectedRecordHeader` | Workspace entity banner — surface background, bottom divider, title + subtitle + badge row. Used in Module and DocType detail views. |
| `RecordCollectionHostView` + `RecordWorkspaceToolbarContent` | Shared workspace chrome for all metadata record collections. |
| `DocTypeBuilderView` | Restructured into three groups: Basic Info / Schema (tabbed: Fields, Permissions) / Configuration (Sync + Indexes). Collections use compact list rows with inline expand-on-select editors. |

Both `Modules` and `DocTypes` route through `RecordCollectionHostView`, so all shared chrome improvements (toolbar, view modes, `SelectedRecordHeader`) apply to both without duplication.

### 2.18 Reporting — §5.2

- **Partial** — `ReportEngine.register`, `availableReports`, `execute`. Comment in code admits "role-based filtering can be layered on top … once role annotations are added"; today, `availableReports(for:)` ignores its argument.

### 2.19 Cloud Adapter — §5.3

- **Shipped** — Protocol defined (ADR-018) with a `NoOpCloudAdapter` default. Correctly labelled planned at the implementation level (no concrete backend).

---

## 3. Test coverage

- **XCTest tests written in `mercantis coreTests/`.** Covers `ExpressionEvaluator`, `MetaComposer`, `ConflictResolver`, `ValidationPipeline`, `DocumentEngine` (save/fetch/concurrency/submit/cancel/amend), `MigrationRunner` (v1–v6 + idempotency), `Naming`, `Automation`, `ExtensionPoints`, and `Scheduler` (cron parser, persistence, due-check, ExtensionSchedulerRegistrar conformance, end-to-end through `AppInstaller`).
- **Wire-up pending.** The test target does not yet exist in `project.pbxproj`. `mercantis coreTests/README.md` lists the one-time Xcode setup. After that, `⌘U` or `xcodebuild test` runs the suite.
- Other subsystems remain intentionally uncovered until their implementation settles (see P0.2/P0.5 in `Docs/ENHANCEMENT-PROPOSAL.md`).

---

## 4. SwiftPM products

`Package.swift` declares two products:

- `.library(name: "MercantisCore", targets: ["MercantisCore"])` — the engine, importable via `.package(url:from:)`. The target points at `mercantis core/` with `exclude: ["Assets.xcassets", "mercantis_coreApp.swift", "UIShell", "Views"]`, so SwiftUI / app-shell code is deliberately not part of the library. GRDB (`https://github.com/groue/GRDB.swift`, `from: "6.0.0"`) is declared on the library target. Shipped in P2.6 (2026-04-25).
- `.executable(name: "mercantis", targets: ["mercantis"])` — the CLI. Continues to use `MercantisCLI/SQLite3` as a system library; consolidating onto `MercantisCore` is P2.3.

Notes on consumers:
- The Xcode app target (`mercantis core`) still compiles the engine source via project membership rather than via the SwiftPM library. The `.library` declaration is sufficient for Hub to consume Core today; migrating the Xcode app to consume the SwiftPM library is a `.pbxproj` change best done in Xcode itself.
- The XCTest files in `mercantis coreTests/` use `@testable import mercantis_core` (the Xcode app module name) and are not yet wired as a SwiftPM test target. P0.1 tracks the Xcode-side wire-up.

## 5. The MercantisCLI target

`MercantisCLI/` is a separate SwiftPM executable built on `swift-argument-parser`. Commands:

- `new-app` — scaffold a manifest.
- `new-doctype` — scaffold a DocType, optionally append to a manifest.
- `install-app` — write a manifest into the SQLite database (bypasses the Swift `AppInstaller`; uses its own `SQLiteDatabase` support class).
- `migrate`, `create-patch`, `run-patch` — data-patch flow.
- `list-apps`.

This is a useful parallel tool but also a **duplicate installer code path**. The app's `AppInstaller.swift` and the CLI's `InstallApp.swift` share no code, so schema drift between the two is possible.

---

## 6. Summary for new contributors

If you open the repo today expecting to find everything ARCHITECTURE.md §7 advertises, here is the short list of what _to stop looking for_:

- `Cache/`, `Files/`, `ImportExport/`, `Printing/` — do not exist. (`Naming/` shipped P1.1 — see §2.11; `Automation/` shipped P1.2; `Scheduling/` shipped P1.4 — see §2.12.)
- A chain-style `PermissionEvaluator` protocol — does not exist; `PermissionEngine` is a flat class, and §4.4 / ADR-011 now describe it as such (P0.5).
- AST in `ExpressionEvaluator` — does not exist; direct-eval recursive descent.
- Role-filtered `availableReports` — does not exist; returns all.
- Any XCTest target — does not exist.

Everything else in the doc is at least partially real. The _engine_ is in good shape; what remains is host-app wiring (constructing `AppInstaller` / `SchedulerService` at launch) and the `Files` / `Printing` / `ImportExport` subsystems. Naming shipped in P1.1 (§2.11); extension-point resolution — the load-bearing wiring that binds manifest-declared events into `EventEmitter` — shipped in P1.3 (§2.9); the automation runtime shipped in P1.2 (§2.12); the periodic-task scheduler shipped in P1.4 (§2.12).
