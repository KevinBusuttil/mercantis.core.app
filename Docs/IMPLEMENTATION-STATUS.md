# Implementation Status

_Last updated: 2026-04-22_

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
| `ExpressionEngine/` | Yes | See note below on AST claim. |
| `Files/` | **No** | §4.18 describes `File.swift`, `FileManager.swift`. Neither exists. |
| `ImportExport/` | **No** | §4.20 describes `DataImporter.swift`, `DataExporter.swift`. Neither exists. |
| `Metadata/` | Yes | Matches §4.1. |
| `Naming/` | **No** | §4.11 / ADR-014 describe `NamingStrategy`, `UUIDv7Strategy`, `NamingSeriesStrategy`, `FieldDerivedStrategy`, `PromptStrategy`, `FormatStrategy`, `NamingService`, `DocumentNamingRule`. None exist. `DocType.autoname: String?` is the only breadcrumb, and it is unused in save flow. |
| `Notifications/` | Yes | Has **both** `EventBus.swift` (ADR-012, superseded) and `EventEmitter.swift` (ADR-020). `DocumentEngine` still requires an `EventBus` in its initializer, so the old path has not been retired. |
| `Permissions/` | Yes (shape doesn't match) | Only `PermissionEngine.swift`. Missing `PermissionContext.swift`, `PermissionEvaluators.swift`. See §4.4 deviation below. |
| `Printing/` | **No** | `LetterHead.swift`, `PDFGenerator.swift`, `PrintFormat.swift` absent. (Docs correctly mark §4.17 _planned_, but §7's tree still lists them.) |
| `Reporting/` | Yes | `ReportEngine.swift` only. |
| `Scheduling/` | **No** | §4.13 describes `SchedulerService.swift`, `ScheduledTask.swift`. Neither exists. |
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
- **Shipped** — `ValidationPipeline` protocol + stages (ADR-022): type coercion, required, link, unique, expression rule, workflow guard, permission. All seven are present and composed in `DocumentEngine.save`.
- **Partial** — `list(docType:filters:)` filters are equality-only. No sort, no limit, no LIKE/range, despite `§4.15` advertising `sortBy:limit:`.
- **Partial** — `audit_log` table is created in the migration but nothing writes to it. §4.3 describes it as "the immutable audit trail of all document mutations"; in practice the sync queue is acting as that log.

### 2.3 Storage — §4.3

- **Shipped** — `MercantisDatabase`, `MigrationRunner`. Three versioned migrations: **v1** creates the advertised tables (`doctypes`, `fields`, `documents`, `document_children`, `sync_queue`, `audit_log`, `apps`, `workflows`); **v2** adds `docStatus` + `amendedFrom` columns (ADR-013); **v3** adds `document_versions` (ADR-024).
- **Partial** — Migrations are forward-only (as intended) but there is no test suite asserting schema shape.
- **Partial** — `audit_log` has neither a writer nor a reader API. Created, never used.

### 2.4 Permissions Engine — §4.4 (documentation gap)

**The documentation and ADR-011 describe something the code doesn't implement.**

| Docs say | Code has |
|---|---|
| `PermissionEvaluator` protocol + `PermissionDecision` enum | Neither exists. |
| Evaluator chain (`AppLevel`, `DocTypeLevel`, `FieldLevel`, `RowLevel`, `WorkflowLevel`) | A flat class `PermissionEngine` with three hard-coded methods. |
| Row-level arbitrary condition filter | `canAccessRow(document:userRoles:rowFilter:)` only does equality match on a `[String: FieldValue]` dict. No expression support. |
| AppLevel evaluator | Not implemented. Nothing checks "is the user's role allowed to use this module/app at all?". |
| WorkflowLevel evaluator | Workflow role checks happen inside `WorkflowEngine.availableTransitions`, not via an evaluator. |

The `ValidationPipeline`'s `PermissionStage` calls into `PermissionEngine.canPerform`, so the pipeline does integrate — but the overall model in the doc is aspirational. **Either implement the chain or rewrite §4.4 + ADR-011 to describe what is actually there.**

### 2.5 Workflow Engine — §4.5

- **Shipped** — `availableTransitions`, `transition`, transition-history records, event emission.
- **Partial** — `WorkflowTransitionHistory` is produced and returned to the caller but is **not persisted** anywhere in `WorkflowEngine`; it's up to the caller to store it. §4.5 implies it's recorded automatically.

### 2.6 Sync Engine — §4.6 / ADR-005 / ADR-006

- **Shipped** — Push of pending mutations, pull of remote mutations, per-DocType sync-policy lookup, `ConflictResolver` with LWW / VCM / AO.
- **Shipped** — `CloudAdapter` protocol + `NoOpCloudAdapter`.
- **Partial** — `lastServerSequence` is kept in-memory only. A code comment says "a production version would store this in SQLite". Every process restart will re-pull everything the adapter knows about.
- **Partial** — Remote mutations are stored in `sync_queue` with status `applied`, never pruned. The queue grows without bound.
- **Partial** — `applyRemoteUpsert` overwrites the local document row without running it through `DocumentEngine.save`, so the `ValidationPipeline`, `DocumentVersion` diff tracking, and submit-immutability guard do **not** fire on sync-received writes. This is a real divergence from ADR-024 ("on every save").
- **Partial** — `resolveConflict(docType:documentId:chosenVersion:resolvedBy:)` appends a `resolveConflict` mutation but does not load the chosen version's payload — the document row is left as whatever the last write set it to.

### 2.7 Expression Engine — §4.7 / ADR-017

- **Partial** — Hand-rolled tokeniser + recursive-descent parser that **evaluates inline**. There is no AST type, no intermediate representation, and therefore no static field-reference analysis, no constant folding, and no source-position errors. The doc's "typed AST" claim is aspirational.
- **Partial** — `FieldValue` has cases `.string`, `.int`, `.double`, `.bool`, `.null`. No `.date`, `.dateTime`, `.data`, `.array`. Already captured in the ARCHITECTURE-CHANGELOG follow-up list.
- **Partial** — Numeric literal parsing consumes `-` only when it is the first token, so `a - 1` tokenises fine but `1 + -2` does not. Unary minus is not supported mid-expression.
- **Partial** — No `lookup(docType, name, field)` (also already on the follow-up list).

### 2.8 Notifications & Events — §4.8 / ADR-020

- **Shipped** — `EventEmitter`, `MercantisEvent` marker protocol, concrete event types (`DocumentSavedEvent`, `DocumentDeletedEvent`, `DocumentSubmittedEvent`, `DocumentCancelledEvent`, `DocumentAmendedEvent`, `WorkflowTransitionEvent`, `AppInstalledEvent`).
- **Partial** — `EventBus.swift` (ADR-012, superseded) **still exists and is still required by `DocumentEngine.init` and `WorkflowEngine.init`**. `EventEmitter` takes a `legacyBus:` in its initialiser to bridge. The migration is halfway done.
- **Missing** — In-app `NotificationLog` DocType, notification rules, email/SMS/webhook channels described in §4.16. §4.16 itself says "in progress".

### 2.9 App Runtime — §4.9 / §4.12

- **Shipped** — `AppManifest` (Codable), `AppInstaller.install(_:)`, `AppInstaller.uninstall(appId:)`, `installApp` mutation flow.
- **Missing** — §4.12's Layer-1 declarative resolution at install time: `documentEventSubscriptions`, `schedulerEvents`. `AppInstaller` does not read these keys from the manifest; `AppManifest` does not even declare them. ADR-015 / ADR-026 promise this; the runtime has no hook into it.

### 2.10 Document Lifecycle — §4.10 / ADR-013

- **Shipped** — Submit / Cancel / Amend flow with correct docStatus transitions and the cancel link-integrity guard.
- **Partial** — `amend` creates a new Draft with `amendedFrom` set (verified in DocumentEngine). Amendment audit lineage is captured, but not surfaced in `DocumentVersion`.

### 2.11 Naming System — §4.11 / ADR-014

- **Missing entirely.** No `NamingStrategy` protocol, no registry, no strategies, no `NamingService`, no `DocumentNamingRule`. `DocType.autoname: String?` is the only field; it is decoded and stored but never consumed. IDs are generated by callers (usually `UUID().uuidString`).

### 2.12 Scheduling & Automation — §4.13 / ADR-019 / ADR-025

- **Missing entirely.** No `SchedulerService`, no `ScheduledTask`, no `AutomationActionRegistry`, no `AutomationActionHandler`, no built-in actions. `AppManifest.automationRules: [AutomationRule]` decodes but has no runtime that executes them.

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
- **Note** — UIShell is by far the largest subsystem (~4,900 lines — `NavigationShell.swift` alone is 925, `DocTypeBuilderView.swift` 905, `FormBuilderView.swift` 786). The core engine (DocumentEngine + SyncEngine + ExpressionEngine) totals ~1,850 lines. The balance of effort is ~60% UI, ~20% engine, ~20% everything else.
- **Partial** — `AppManifest.dashboards: [DashboardDefinition]` decodes into the manifest, but there is no `DashboardView` or dashboard rendering code. The type exists; the runtime does not.
- **Footgun** — `DocTypeBuilderView.swift:35` does `fatalError` when the metadata DB won't open. Acceptable for a builder surface, but it's the only `fatalError` in the codebase.

### 2.18 Reporting — §5.2

- **Partial** — `ReportEngine.register`, `availableReports`, `execute`. Comment in code admits "role-based filtering can be layered on top … once role annotations are added"; today, `availableReports(for:)` ignores its argument.

### 2.19 Cloud Adapter — §5.3

- **Shipped** — Protocol defined (ADR-018) with a `NoOpCloudAdapter` default. Correctly labelled planned at the implementation level (no concrete backend).

---

## 3. Test coverage

- **No test target.** `project.pbxproj` has exactly two native targets: the app (`mercantis core`, iOS/macOS app) and the CLI (`MercantisCLI`, tool). No `XCTest` target, no `*Tests` folder anywhere.
- Every ADR that introduces a new subsystem claims "independently testable" (ADR-011, ADR-022 in particular). None of it is tested.

This is by far the biggest risk compounder: the ValidationPipeline and ConflictResolver have exactly the shape that rewards unit testing, and get none.

---

## 4. The MercantisCLI target

`MercantisCLI/` is a separate SwiftPM executable built on `swift-argument-parser`. Commands:

- `new-app` — scaffold a manifest.
- `new-doctype` — scaffold a DocType, optionally append to a manifest.
- `install-app` — write a manifest into the SQLite database (bypasses the Swift `AppInstaller`; uses its own `SQLiteDatabase` support class).
- `migrate`, `create-patch`, `run-patch` — data-patch flow.
- `list-apps`.

This is a useful parallel tool but also a **duplicate installer code path**. The app's `AppInstaller.swift` and the CLI's `InstallApp.swift` share no code, so schema drift between the two is possible.

---

## 5. Summary for new contributors

If you open the repo today expecting to find everything ARCHITECTURE.md §7 advertises, here is the short list of what _to stop looking for_:

- `Automation/`, `Cache/`, `Files/`, `ImportExport/`, `Naming/`, `Printing/`, `Scheduling/` — do not exist.
- `PermissionEvaluator` chain — does not exist; `PermissionEngine` is a flat class.
- AST in `ExpressionEvaluator` — does not exist; direct-eval recursive descent.
- Role-filtered `availableReports` — does not exist; returns all.
- Persisted `lastServerSequence` — does not exist; in-memory only.
- Any XCTest target — does not exist.

Everything else in the doc is at least partially real. The _engine_ is in good shape; the _shell around the engine_ (naming, scheduling, automation runtime, automated events from manifests) is the gap.
