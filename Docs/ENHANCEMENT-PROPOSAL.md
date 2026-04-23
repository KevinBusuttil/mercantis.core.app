# Enhancement Proposal

_Last updated: 2026-04-23_

Companion document to [`IMPLEMENTATION-STATUS.md`](./IMPLEMENTATION-STATUS.md). The status doc catalogues _what is_; this doc proposes _what to do next_. Each item is labelled with effort (S/M/L), risk, and the ADR or architecture section it closes.

Principles guiding the ranking:

1. **Test before expand.** The engine has ~1,850 lines of unclaimed territory with no tests; every new subsystem doubles the test deficit.
2. **Close the drift first.** Docs that describe things that don't exist erode trust faster than missing features. Either implement or demote to "planned".
3. **Finish the sync story before starting the automation story.** Automation depends on the mutation log being sound; the mutation log has real issues today.

---

## P0 — Correctness & trust

These are either doc-vs-code drift or latent correctness issues. None add features.

### P0.1 — Add an XCTest target [M, low risk] — infra *(tests landed; target wire-up pending)*

Test source is now in `mercantis coreTests/`:

- `ExpressionEvaluatorTests.swift` — boolean, formula, comparisons, unary minus (P0.9 regression), division by zero, undefined field, empty input.
- `ValidationPipelineTests.swift` — each stage in isolation plus short-circuit ordering.
- `MetaComposerTests.swift` — custom-field insertion, property setters, cache invalidation.
- `ConflictResolverTests.swift` — LWW / VCM / AO across equal / newer / stale versions.
- `DocumentEngineTests.swift` — save/fetch round-trip, sync-queue atomicity, `DocumentVersion` recording, optimistic concurrency, submit immutability, cancel link integrity, amend.
- `MigrationRunnerTests.swift` — v1/v2/v3 applied in order, expected tables/columns, idempotency, custom-version registration.
- `Support/TestSupport.swift` — shared fixtures (tempdir DB, DocType / Document builders, `DocumentEngine` harness).

**Remaining work:** wire the files into an Xcode Unit Testing Bundle target. Steps are in `mercantis coreTests/README.md`. Once added, the suite runs via `⌘U` or `xcodebuild test`.

Why this was first: every enhancement below lands more safely on top of a test target. The validation pipeline in particular was built for independent stage testing (ADR-022) — shipping it without a test target inverts the intended workflow.

### P0.2 — Run sync-received writes through `DocumentEngine` [M, medium risk] — ADR-005/022/024 *(done)*

`DocumentEngine.applyRemote(_:from:)` now owns the persistence of sync-received upserts. It runs the same `ValidationPipeline` (ADR-022), submit-immutability guard (ADR-013), and `DocumentVersion` diff recording (ADR-024) that local saves do. Remote writes are no longer a bypass path.

Also fixed an adjacent latent bug: `UpsertPayload` was a 4-field projection that dropped the document's fields on push. Both local saves and remote applies now encode/decode the full `Document` in the sync queue payload.

`SyncEngine.applyRemoteUpsert` is now a thin dispatcher: decode → `ConflictResolver` → `.accepted` / `.appendedAsNew` delegate to `applyRemote`; `.conflicted` marks the local row. Coverage lands in `SyncEngineTests.swift`.

**Known follow-up:** `LinkValidationStage` runs on remote writes too, which means out-of-order arrivals (child-before-parent) will be rejected rather than buffered. Assumes the CloudAdapter preserves ordering; document when writing the real adapter.

### P0.3 — Persist `lastServerSequence` [S, low risk] — ADR-005 *(done)*

`SyncEngine.lastServerSequence` now survives process restarts. A new v4 migration adds a small key/value `sync_state` table; the engine loads the bookmark at init and rewrites it (UPSERT) inside the existing write transaction on every pull advance.

Coverage in `SyncEngineTests.swift`:

- `testPullAdvancesAndPersistsLastServerSequence` — after a pull, the `sync_state` row matches the highest `serverSequence` seen.
- `testLastServerSequenceSurvivesSyncEngineRestart` — a second `SyncEngine` built against the same database asks the adapter for mutations strictly after the previously persisted sequence.
- `testLastServerSequenceDefaultsToZeroOnFreshDatabase` — fresh database ⇒ first pull requests from 0.

`MigrationRunnerTests` was extended to assert v4 brings `highestAppliedVersion()` to 4 and creates `sync_state(key, value)`.

The `sync_state` table is a general-purpose key/value store; P0.4 (queue pruning) is expected to add additional keys (e.g., last prune watermark) here without another migration.

### P0.4 — Prune `sync_queue` on acknowledgement [S, low risk] — ADR-028 *(done)*

`SyncEngine.pruneSyncQueue(force:)` now deletes acknowledged mutations under a `SyncQueuePruneConfig` policy:

- `.pushed` (local, server-acknowledged) rows older than `pushedRetention` (default 30 days) are deleted.
- `.applied` (remote, locally-applied) rows older than `appliedRetention` (default 30 days) are deleted.
- `.pending` and `.conflicted` rows are **never** deleted regardless of age.

Throttling: a persisted `"syncQueuePrunedAt"` key in the v4 `sync_state` table skips the run if the previous prune was within `pruneInterval` (default 24 hours). `force: true` bypasses the throttle.

No new timers — `pushPendingMutations()` and `pullAndApplyRemoteMutations()` call `pruneSyncQueue(force: false)` at the end of each successful run, so pruning piggybacks on existing sync activity. No `VACUUM`: the word "vacuum" in this item's original wording referred to scheduling, not the SQLite command.

Decisions are captured in ADR-028. Coverage in `SyncEngineTests.swift`:

- `testPruneRemovesPushedRowsOlderThanRetention`
- `testPruneRemovesAppliedRowsOlderThanRetention`
- `testPruneNeverDeletesPendingOrConflictedRows`
- `testPruneThrottlesWhenCalledWithinInterval`
- `testForcePruneBypassesThrottle`
- `testPruneWatermarkIsPersistedToSyncState`
- `testPushPendingMutationsOpportunisticallyPrunesOldPushedRows`

### P0.5 — Align the Permissions doc with the code [S, medium risk] — ADR-011 *(done — option A, 2026-04-23)*

Option A shipped: §4.4 and ADR-011 now describe the flat `PermissionEngine` — `canPerform(operation:on:userRoles:)`, `canAccessField(fieldKey:on:userRoles:operation:)`, `canAccessRow(document:userRoles:rowFilter:)` — that actually exists, and references to `PermissionEvaluator`, `PermissionDecision`, and the evaluator chain have been removed (or reframed as "not shipped" historical notes) from:

- `ARCHITECTURE.md` §3 (architecture diagram), §4.2 (ValidationPipeline `PermissionStage`), §4.4 (Permissions Engine — fully rewritten), §4.12 (Layer 3 extension protocols), §4.15 (Public API Surface), §7 (directory tree).
- `Docs/ADR/ADR-011-multi-level-permission-model.md` — rewritten to describe the shipped flat surface and its out-of-scope checks (app / module gating; workflow-level role checks remain inside `WorkflowEngine`).
- `Docs/ADR/ADR-025-automation-action-registry.md` — the "consistent with `PermissionEvaluator`" line reframed.
- `Docs/ADR/ADR-026-three-layer-extensibility-model.md` — removed `PermissionEvaluator` from the Layer 3 list; added a note that reintroducing it requires implementing the chain first.
- `Docs/IMPLEMENTATION-STATUS.md` §1, §2.4, §5 — removed "shape doesn't match" entries; §2.4 now reads as a regular Shipped / Partial breakdown.

Option B (implement the chain — introduce a `PermissionEvaluator` protocol, five concrete evaluators, and a chain runner; replace `PermissionStage` to call the chain) remains the stated long-term direction, scheduled alongside:
- **P1.7** — row-level expression support (`canAccessRow` predicate via `ExpressionEvaluator`).
- **App-/module-level gating** — not yet in the engine; a future ADR.

Until then, §4.4 / ADR-011 accurately document what ships.

### P0.6 — Resolve `EventBus` / `EventEmitter` duality [S, low risk] — ADR-020

`EventBus.swift` is still alive and `DocumentEngine`/`WorkflowEngine` still require it in their init. The replacement is in place; finish the job:
1. Delete the `eventBus` parameter from `DocumentEngine.init` and `WorkflowEngine.init`.
2. Remove `EventEmitter(legacyBus:)` and the legacy bridge.
3. Delete `EventBus.swift`.
4. Update call sites in `mercantis_coreApp.swift` / CLI / any tests.

ADR-012 already says "superseded"; the code should reflect it.

### P0.7 — Update ARCHITECTURE.md §7 directory tree [S, zero risk] — doc hygiene

- Remove directories that don't exist (`Automation/`, `Cache/`, `Files/`, `ImportExport/`, `Naming/`, `Printing/`, `Scheduling/`) or clearly mark them "(planned — not on disk)".
- Add `Views/DesignSystem/` to the tree with its "demo-only" caveat.
- Correct the `DocumentEngine.list` signature in §4.15 to `list(docType:filters:)`.
- Correct the `PermissionEngine.canPerform` signature in §4.15 to `canPerform(operation:on:userRoles:)`.
- (Already done in this changeset: ADR-027 added to §8.)

### P0.8 — `DocumentVersion` stores the full old/new not just a diff summary [S, low risk] — ADR-024 *(done — 2026-04-23)*

`DocumentEngine` now exposes two reader APIs that make the append-only `document_versions` history consumable:

```swift
public func versions(of documentId: String) throws -> [DocumentVersion]
public func version(of documentId: String, at timestamp: Date) throws -> DocumentVersion?
```

`versions(of:)` returns the full history ordered oldest first. `version(of:at:)` returns the version that was **in effect at** `timestamp` — the most recent version with `savedAt <= timestamp` — or `nil` if no version was recorded at or before that instant. Both read straight from the v3 `document_versions` table; saves that produce no field changes still do not write a row, so the history surface matches the write path one-for-one.

Coverage in `DocumentEngineTests.swift`:

- `testVersionsReturnsEmptyForUnknownDocument`
- `testVersionsReturnsChronologicalHistoryWithCorrectDiffs`
- `testVersionAtBeforeFirstSaveReturnsNil`
- `testVersionAtReturnsLatestSaveAtOrBeforeTimestamp`
- `testSaveWithoutFieldChangesDoesNotAppendAVersion`

### P0.9 — Fix unary minus in `ExpressionEvaluator` [S, low risk] — ADR-017

The tokeniser treats `-` as a negative-number prefix only when `tokens.isEmpty`. `1 + -2` is parsed as `1`, `+`, `2` (silently wrong). Make unary minus a real parser case in `parseFactor` / `parseUnary`. Cover with `ExpressionEvaluatorTests`.

---

## P1 — Close the obvious feature gaps

These are features the docs promise and apps will reasonably assume exist.

### P1.1 — Implement the Naming subsystem [M, low risk] — ADR-014 / §4.11

`DocType.autoname` is decoded but unused, so every document's ID comes from the caller. Minimum to honour the ADR:

```
mercantis core/Naming/
├── NamingStrategy.swift         // protocol + resolve(docType:document:context:)
├── NamingService.swift          // strategy registry + DocumentNamingRule evaluation
├── UUIDv7Strategy.swift         // default
├── NamingSeriesStrategy.swift   // parse SINV-.YYYY.-.####, use a counter row in a new `naming_counters` table
├── FieldDerivedStrategy.swift
├── PromptStrategy.swift         // throws if no caller-supplied name in context
└── FormatStrategy.swift
```

Wire `NamingService.resolve(...)` into `DocumentEngine.save` **before** persist, when `document.id` is empty. Add a `naming_counters` migration (v4) for the series strategy.

**Effort caveat:** Time-token expansion (`YYYY`, `MM`, `DD`) is trivial; concurrent `.####` increments under offline use need the sync queue to carry the counter update, otherwise two devices both start at `SINV-2026-0001`.

### P1.2 — Implement the Automation runtime [L, medium risk] — ADR-019 / ADR-025

`AppManifest.automationRules` decodes but nothing executes them. Minimum viable:

```
mercantis core/Automation/
├── AutomationActionHandler.swift    // protocol: actionType, execute(document:parameters:context:)
├── AutomationActionRegistry.swift   // register / lookup / execute
├── BuiltInActionHandlers.swift      // SetValueHandler, SetStatusHandler, SendNotificationHandler (log-only for now), ValidateHandler, AssignHandler
└── AutomationRunner.swift           // subscribes to DocumentSavedEvent / DocumentSubmittedEvent, matches rules, dispatches handlers
```

Depends on P1.3 (extension-point resolution) to actually bind a manifest's rule set to the event bus at install time.

### P1.3 — Implement extension-point resolution at install time [M, medium risk] — ADR-015 / ADR-026

`AppManifest` does not yet declare `extensionPoints`. Add:

```swift
public struct ExtensionPoints: Codable, Sendable {
    public var documentEventSubscriptions: [DocumentEventSubscription]
    public var schedulerEvents: [SchedulerEventDeclaration]
}
```

…and in `AppInstaller.install`, for each declaration:
- Resolve the handler against the action registry.
- Subscribe the resulting closure to `EventEmitter` (or register with `SchedulerService`).
- Keep the returned `SubscriptionToken`s in a per-app dictionary so `uninstall` can release them.

This is the load-bearing piece that turns the declarative model from a pretty JSON document into a running system.

### P1.4 — Implement the Scheduler [M, medium risk] — §4.13

```
mercantis core/Scheduling/
├── ScheduledTask.swift              // type, handler, retryPolicy
├── SchedulerService.swift           // cron/interval matcher; due-check on launch + every 60s while active
└── SchedulerPersistence.swift       // `scheduler_state` table: lastRun per task key
```

Cron support is the only non-trivial piece. A dependency-free subset (minute, hour, day-of-month, month, day-of-week, no `@yearly` aliases) covers Frappe's typical use and fits in ~200 lines.

### P1.5 — Turn `WorkflowGuardStage` and `PermissionStage` into real stages [S, low risk] — ADR-022

Both are placeholders that comment-document the gap. Fold them in:
- `WorkflowGuardStage` — given the current document and its target `docStatus`/status transition, verify the transition is declared in the `WorkflowDefinition` and the user has the role. Reject with a typed error if not.
- `PermissionStage` — once P0.5 option B lands, call `PermissionEngine.canPerform(operation: .write, on: docType, userRoles:)`. Until then, wire the existing flat methods.

### P1.6 — Expand `FieldValue` [S, low risk] — ARCHITECTURE-CHANGELOG follow-up

Add `.date(Date)`, `.dateTime(Date)`, `.data(Data)`, `.array([FieldValue])`. Decoder needs a disambiguation key (currently `FieldValue` is likely coded as a tagged enum — confirm during the changeset). This is a prerequisite for P2.8 (richer field controls) and for `FieldType.date` / `FieldType.datetime` to round-trip correctly rather than relying on string encoding.

### P1.7 — Row-level permissions take a condition expression [M, medium risk] — ADR-011

Today `canAccessRow` is an equality dict. Per the doc ("arbitrary condition filter"), it should accept an expression:
```swift
canAccessRow(document:, userRoles:, rowExpression: String?) -> Bool
```
…evaluated via `ExpressionEvaluator` over the document's fields plus a `user.*` namespace. Lands cleanly after P1.6 and gives real row-level security without writing new code per DocType.

---

## P2 — Structural improvements

### P2.0 — Metadata workspace UX refactor [S, low risk] — ADR-016 / ADR-027 ✅ shipped 2026-04-23

**Rationale:** `DocTypeBuilderView`, `Modules`, and `DocTypes` shared the same workspace chrome but did not read as one coherent family. Section headers (`MercantisSectionHeading`) were visually noisy and chrome-heavy.

**Implemented:**

- `MercantisSectionHeading` redesigned as a genuine structural header: uppercase tracking text, no background fill, no border-radius. Looks like a macOS grouped-table section label, not a button.
- `DocTypeBuilderView` restructured into three logical groups:
  - **Basic Info** — compact card for DocType ID, name, module, title field, search fields, flags.
  - **Schema** — segmented tab (`Fields` / `Permissions`). Each collection renders compact single-line summary rows (key · type · Required badge; role · R/W/C/D/S/A matrix). Selecting a row expands the editor inline.
  - **Configuration** — sync policy card + compact Indexes collection, clearly separated from the schema concerns above.
- `SelectedRecordHeader` given a surface background and bottom divider, making it a proper workspace entity banner. Shared by both Modules and DocTypes detail views.
- `moduleSelectedRecordHeader` (NavigationShell) enriched with a `subtitle` ("Custom Module" / "System Module") and a DocType count badge derived from existing `tooling.navigableDocTypes`. No invented data.
- External padding removed from `RecordCollectionHostView`'s `detailHeader` slot to avoid double-padding now that `SelectedRecordHeader` carries its own padding.

**Non-goals respected:** no nav model change, no design-lab promotion, no fake dashboards, no extra color, FormBuilderView left structurally intact.

### P2.0a — Unify record creation as a modal sheet across all entry points [S–M, low risk] — UX ✅ shipped 2026-04-23

**Rationale:** "New" currently does three different things depending on where the user invokes it.

| Entry point | Today | File |
|---|---|---|
| DocTypes workspace → New | `.sheet` presents `DocTypeBuilderView` (correct) | `DocTypeListView.swift:31-34, 60-71` |
| Quick Create → "New Doctype" | `router.openDocType(...)` + pre-loads `activeDocument` in the generic `docTypeDetail` path, bypassing `DocTypeListView` | `NavigationShell.swift:310-317, 364-390` |
| Command Bar → "New <X>" | Same as Quick Create | `NavigationShell.swift:575-588` |
| Generic workspace toolbar → New | `RecordCollectionHostView.handleCreateDocument()` switches to `.detail` view mode and inlines `GenericFormView` | `RecordCollectionHostView.swift:186-194` |

So for `Doctype` specifically — and for every other DocType — whether the user sees a proper modal or an inline-draft-in-the-content-pane depends on *which door they walked through*. This is a UX consistency problem and a latent bug surface (the inline path bypasses the sheet's discard guard).

**Implemented:**

- `CreateRecordSheet` — new sheet primitive (`UIShell/CreateRecordSheet.swift`) that hosts `GenericFormView` on a draft document with a macOS-style header (title "New <DocType.name>", module subtitle, Cancel / Save buttons). Discard guard built in.
- `RecordCollectionHostView` — `handleCreateDocument` no longer mutates `selectedViewMode`. Instead it sets `createSheetDraft`, which drives a `.sheet(item:)` presenting `CreateRecordSheet`. `onSave` commits via `tooling.saveDocument`, then selects the new record and dismisses.
- `UIShellRouter` — new `pendingCreate: String?` published property plus `requestCreate(docTypeId:module:)` / `consumePendingCreate(_:)`. `requestCreate` navigates to the workspace responsible for the target DocType, then signals `pendingCreate`; `RecordCollectionHostView.onAppear` consumes it and fires `handleCreateDocument`.
- Quick Create (`NavigationShell.swift`) and Command Bar now call `router.requestCreate(...)` instead of `router.openDocType(...)` + `activeDocument = tooling.createDraftDocument(...)`. No more pre-loaded inline drafts.
- `DocTypeListView` keeps its bespoke `DocTypeBuilderView` sheet (authoring DocType metadata is not a generic-form task) but now also listens to `router.pendingCreate == BuiltInDocTypes.docType.id` and re-routes through the same `CreateRecordSheet` path for cross-entry-point consistency.

**Non-goals respected:** no changes to `FormBuilderView` or the visual-builder window; editing remains inline in detail/browse; no nav model changes beyond the `pendingCreate` signal.

### P2.1 — Turn the ExpressionEvaluator into a real AST [M, low risk] — ADR-017

`ARCHITECTURE.md` §4.7 already advertises this ("typed AST", static field-reference analysis, constant folding, source positions). Lift the current evaluator to a two-phase design:

1. `Parser` — produces `ExpressionNode` (enum: `literal`, `fieldRef`, `binaryOp`, `unaryOp`, `call`). Records source `Range<String.Index>` per node.
2. `Evaluator` — walks the AST with a typed `ExprValue` result.

Immediate wins:
- `MetaComposer` can call `Parser.referencedFields(expression:)` and fail validation at install time if an expression references a field the DocType does not declare.
- `visibilityExpression` / `readOnlyExpression` can be cached (parsed once per DocType load, evaluated per document).
- Errors include a caret position instead of "unexpectedToken".

### P2.2 — Cross-document `lookup(docType, name, field)` [M, medium risk] — ARCHITECTURE-CHANGELOG follow-up

Frequently requested Frappe feature. Requires a decision: cache-by-read, or force explicit fetch? Recommend cache-by-read with per-save invalidation (already how `MetaComposer` works). Needs an ADR.

### P2.3 — Consolidate `AppInstaller` and CLI `install-app` [M, medium risk] — CLI/app parity

Currently there are two independent install paths (one via GRDB in the app, one via raw `sqlite3` in `MercantisCLI/Sources/Support/SQLiteDatabase.swift`). They will drift. Extract the mutation-query set into a shared target (or at minimum a tested reference implementation) that both paths call.

### P2.4 — Dashboard runtime [L, medium risk] — §5.1

`DashboardDefinition` and `DashboardWidget` are declared in `AppRuntimeTypes.swift`. `AppManifest.dashboards` decodes correctly. The type layer exists; the runtime does not. `IMPLEMENTATION-STATUS.md §2.17` confirms: "The type exists; the runtime does not."

This item should not be scoped as "add a view that renders some widgets". It should be scoped as a **reusable dashboard runtime** that any installed module — including Mercantis Hub — can populate from its manifest without writing custom Swift UI code.

Minimum viable capabilities for an ERP module home page and operational dashboard:

- **Number / KPI widget** — a single labelled aggregate (count, sum, latest value) sourced from `ReportEngine.execute` or `DocumentEngine.list`. Supports configurable threshold colouring.
- **List widget** — compact recent-records or pending-tasks surface with a configurable DocType, filter set, and column list. Navigates into the relevant workspace row on tap.
- **Chart-ready extensibility** — a widget protocol slot that accepts an external chart data provider. The runtime does not need to bundle a charting library, but it must expose a stable protocol so Hub or a third-party module can satisfy it without forking the dashboard layer.
- **Drilldown / navigation hooks** — tapping a KPI or a list row calls into `UIShellRouter` to open a filtered `GenericListView` or a specific document. This requires `UIShellRouter` integration at the widget protocol level.
- **Module landing pages** — the dashboard runtime must be the default home surface for any installed module that declares a `DashboardDefinition`. `AppManifest.dashboards` already declares this intent; the runtime must deliver it as a first-class navigation destination, not as a demo-only surface in `Views/DesignSystem/`.

Until this is in place, every module home page falls back to `GenericListView`, which is functional but not a dashboard.

### P2.5 — List filters / sorting / paging [S, low risk] — §4.15

`DocumentEngine.list(docType:filters:)` is equality-only. Add `sortBy:`, `limit:`, and `where:` (expression) to match the advertised signature. The index definitions in `IndexDefinition` exist but are not yet used by the list path.

### P2.6 — Productize Core as a reusable library target [M, low risk] — ADR-007

`Package.swift` currently declares a single `.executable` product (`mercantis`) that wraps `MercantisCLI/Sources`. The `mercantis core/` engine exists as an embedded Xcode framework target inside `mercantis.core.app.xcodeproj`, but there is **no `.library` product in `Package.swift`** that Hub — or any third-party app — could reference with a standard `.package(url:from:)` dependency.

ADR-007 states: "Mercantis Hub is structured as an Xcode project that imports Core as a Swift package or embedded framework." That presupposes an importable, versioned package product. Right now the Core/Hub boundary is architecturally correct but not mechanically enforced. Hub cannot `import MercantisCore` from a resolved Swift package dependency because no such product exists.

Required work:
- Extract `mercantis core/` source files into a proper `.library` target in `Package.swift` (e.g. target name `MercantisCore`).
- Declare a `.library(name: "MercantisCore", targets: ["MercantisCore"])` product.
- Audit `public` vs. `internal` access modifiers deliberately — every `public` member becomes part of the enforced API surface that Hub (and any third party) must use. Internal implementation details become un-importable by design.
- The CLI target (`mercantis`) continues as an `.executable` that declares a dependency on `MercantisCore`.
- The Xcode app target (`mercantis core`) becomes a consumer of the `MercantisCore` package target.

Until this is done, the Core/Hub split is aspirational: the right design, but not an enforced Swift module boundary. ADR-007's "public/internal boundary in Core is enforced by the Swift module system" consequence is not yet true.

### P2.7 — Hub-on-Core readiness: what is sufficient vs. what is still missing [S, low risk] — ADR-007

This is a gap-analysis item, not a criticism of ADR-007. The direction in ADR-007 is correct. The question is: *how much of it is already true?*

**What is strong enough to start Hub today:**

The engine core — `DocumentEngine`, `WorkflowEngine`, `ValidationPipeline`, `PermissionEngine`, `SyncEngine`, `MetaComposer`, `AppInstaller`, and the `GenericFormView` / `GenericListView` shell — is in good working order, covered by tests, and sufficient to build Hub's back-office document foundations. Starting Hub now, against the current public API, is the right way to discover which Core capabilities are missing or incomplete. ADR-007 anticipated this: "if Hub needs functionality that Core does not yet provide, the correct approach is to extend Core's public API".

**What is not yet sufficient to claim ADR-007 is fully realised:**

The subsystems explicitly recorded as missing in `IMPLEMENTATION-STATUS.md` are not cosmetic. Several are load-bearing for any non-trivial ERP module:

| Missing subsystem | Why it matters for Hub |
|---|---|
| Naming (ADR-014, P1.1) | Every Hub document — Invoice, Sales Order, Purchase Order — needs a series name like `SINV-2026-00001`, not a raw UUID caller-supplied ID. |
| Automation runtime (ADR-019/025, P1.2/P1.3) | "On submit, deduct stock" is a basic ERP rule. Without the automation runtime, every such rule must be hard-coded in Hub's own Swift — which is exactly what ADR-007 prohibits. |
| Files / Attachments (§4.18, P3.1) | Attaching PDFs, images, and supplier documents to records is table-stakes for back-office ERP. |
| Import / Export (§4.20, P3.3) | Opening-balance imports and data migration are day-one practical needs for any real deployment. |
| Printing / PDF (§4.17, P3.2) | Invoices, purchase orders, and delivery notes must be printable. |
| Dashboard runtime (§5.1) | Module home pages need more than `GenericListView`. Without it, every Hub module lands on a flat list. |

The conclusion is: **start Hub, extend Core as you hit walls, and treat the gap table above as the real completion criteria for ADR-007 — not a reason to delay starting**.

### P2.8 — Richer field/control model for ERP-grade UI [M, medium risk] — ADR-003 / §4.1

`GenericFormView` renders metadata-driven forms today from the `FieldType` taxonomy in `FieldDefinition.swift`. The current set — `text`, `longText`, `number`, `decimal`, `currency`, `boolean`, `date`, `datetime`, `email`, `phone`, `select`, `multiselect`, `link`, `table`, `attachment`, `status`, `formula` — is a solid CRUD baseline. It is not sufficient for an ambitious ERP or a good POS.

`FieldValue` is even narrower: `.string`, `.int`, `.double`, `.bool`, `.null`. Date, binary, and array values are not representable without encoding them as strings — which is fragile and defeats type safety downstream (expression evaluation, validation rules, FieldValue expansion in P1.6).

The gap does not need to be closed all at once. Tackle it field-type by field-type as Hub surfaces concrete UI needs. Candidates for near-term addition:

- **Rich text / HTML content** — `longText` renders as a plain `TextEditor`. Structured long-form content (terms, notes, descriptions) benefits from a richer input surface.
- **Image / media fields** — distinct from `attachment`; a field type that explicitly expects an image and renders a preview inline rather than a file-name label.
- **Better child-table editing UX** — `table` currently maps to `FieldType.table` with a `childDocType`. `GenericFormView`'s handling of child rows is functional but minimal. A proper inline child-table editor (add/remove/reorder rows, inline cell editing) is essential for order lines, BOM rows, and similar ERP structures.
- **Better link / search picker** — `link` fields currently rely on whatever `GenericFormView` provides for picking a linked document. For high-volume lists (Items, Customers, Suppliers), a type-ahead search picker with configurable display fields is needed.
- **Barcode / QR input** — a field type or input modifier that triggers a barcode scan flow. Essential for stock movements and POS item lookup; closely related to P3.6.
- **Stronger typed `FieldValue`** — blocked on P1.6, but completing P1.6 unlocks proper typed round-trips for `date`, `dateTime`, and `data` values through `DocumentEngine`, `ExpressionEvaluator`, and validation rules.

Do not pre-design the full control taxonomy speculatively. Add types as Hub hits real walls. Each new `FieldType` case requires: type definition, `GenericFormView` rendering branch, `ValidationPipeline` coercion, and test coverage.

---

## P3 — Nice-to-haves & ecosystem

### P3.1 — File/Attachment subsystem [L, medium risk] — §4.18

Only interesting once there's a cloud adapter to sync blobs. Keep as "planned".

### P3.2 — Print & PDF [L, medium risk] — §4.17

Platform-specific (UIKit / AppKit PDF renderers). Keep as "planned".

### P3.3 — CSV/JSON Import / Export [M, low risk] — §4.20

Less risky than it sounds: the import path is just `DocumentEngine.save(_:)` in a loop with a DocType-aware column mapper. Good contribution opportunity; no deep design work.

### P3.4 — `CacheManager` as a real subsystem [M, medium risk] — §4.14

Only if measurable hot paths are found. Premature today — `MetaComposer`'s internal cache is sufficient, and GRDB's prepared statements cover most query cost. Defer until a profiling pass.

### P3.5 — Audit-log reader + writer [S, low risk]

The `audit_log` table exists and nothing writes it. Either repurpose it (the sync queue is already acting as the audit log) and drop the table in a v5 migration, or start writing structured `AuditEntry` rows on every `DocumentEngine` mutation. Decide before the table accumulates implicit meaning.

### P3.6 — POS platform capabilities [L, high risk] — future platform

POS is not a skin over `GenericFormView`. A serious point-of-sale surface has fundamentally different interaction requirements from a back-office ERP form, and several of them require dedicated Core platform work that does not exist yet.

This item should not be started until P1.1 (Naming), P3.2 (Printing), P2.8 (richer field/control model), and P1.2/P1.3 (Automation runtime) are substantially in place. Starting earlier produces a prototype that cannot be deployed.

Capabilities a serious POS requires that Core does not currently support:

- **Fast editable line / cart surface** — a POS transaction is built around rapid row entry (item lookup → quantity → price → running total). `GenericFormView`'s child-table UX is not optimised for this; a dedicated cart component or a substantially enhanced `table`-field editor is needed.
- **Barcode-driven workflows** — scan a barcode, resolve it to an Item via `DocumentEngine.list`, add a line. Requires P2.8 barcode field type, fast `DocumentEngine` lookup (P2.5 filter improvements), and probably a scan-result event pathway through `EventEmitter`.
- **Payment / tender UI** — selecting payment method, splitting tenders, recording change — none of this maps to existing `FieldType` cases. This is a purpose-built UI surface, likely a dedicated `DocType` (e.g. `Payment Entry`) with a custom form layout that `GenericFormView` cannot reasonably drive alone.
- **Receipt / printing path** — requires P3.2 (Printing). A POS receipt is structurally a `PrintFormat` render of a submitted transaction; the print subsystem must exist before POS can close a sale.
- **Touch-friendly interaction patterns** — the current UIShell is designed for macOS pointer input. A POS likely targets iPadOS with touch-primary interaction. That is a different layout density, tap target sizing, and navigation model from what `NavigationShell` currently provides.
- **Offline-first transaction handling** — `SyncEngine` already has an offline-capable mutation queue, but POS demands stronger guarantees: local numbering (Naming, P1.1), local stock reservation, and conflict resolution rules suited to concurrent terminal use. The current `ConflictResolver` (LWW / VCM / AO) is a good starting point but may need POS-specific policies.

Rate this L effort, high risk. Not because it is architecturally impossible on Core, but because it requires the most total platform surface to be in place first, and rushing it produces a demo rather than a deployable feature.

---

## Proposed sequencing

A 4–6 week plan if one engineer is the target:

| Week | Work |
|---|---|
| 1 | P0.1 test target ✅; P0.6 event bus cleanup ✅; P0.7 doc cleanup ✅; P0.9 unary minus ✅. |
| 2 | P0.2 sync-through-engine ✅; P0.3 persisted sequence ✅; P0.4 queue pruning + ADR-028 ✅. |
| 3 | P0.5A (rewrite permissions doc) ✅; P0.5B (implement chain) deferred; P0.8 version reader ✅; P1.5 real validation stages. |
| 4 | P1.1 Naming subsystem (behind a feature flag if needed). |
| 5–6 | P1.2 + P1.3 automation runtime + extension-point resolution. |

P1.4 Scheduler, P1.6 FieldValue expansion, and P1.7 row-level expressions slot in as individual PRs alongside the above.

P2.6 (Core library productization) should happen before Hub development begins in earnest — it is not large work but it is a prerequisite for the Core/Hub boundary being real. P2.7 (Hub readiness gap analysis) is a documentation item that can run in parallel with any P1 work. P2.4 (dashboard runtime) and P2.8 (richer field/control model) are both medium-term items best driven by Hub's concrete needs rather than by speculative pre-design.

P3.6 (POS platform) should not begin until P1.1, P3.2, P2.8, and P1.2/P1.3 are substantially complete. The sequencing dependency is real: a POS without naming, printing, richer controls, and automation is not a POS.

The order matters: testing before refactoring, drift closure before new subsystems, mutation-log soundness before automation that depends on it, Core package boundary before Hub, engine completeness before POS glamour work.

---

## What _not_ to build right now

- **Print & PDF, Files, Cache** — defer. Premature for a platform still closing core loops.
- **WebSocket RealtimeAdapter** — defer until CloudAdapter has a real implementation.
- **More ADRs for existing aspirational features** — the current ADR set already over-describes reality in a few places. Write ADRs when you actually implement (like ADR-023/024 did, which closed real gaps).
- **POS UI** — defer until Naming, Printing, richer field controls, and Automation runtime are in place. Building POS on incomplete foundations produces a demo, not a product.

---

## What is ready vs. what is not yet ready

This is not pessimism. It is roadmap clarity.

**Ready / nearly ready now:**
- Back-office document foundations — save, validate, submit, cancel, amend, sync.
- Metadata-driven admin and setup surfaces — `DocTypeBuilderView`, `FormBuilderView`, module workspace.
- First-party Hub prototype on Core — sufficient engine to start Hub and begin discovering real API gaps.
- Document lifecycle / workflow / permission / report foundations — all partially to fully implemented.
- Conflict-resolved offline sync with a pluggable cloud adapter.

**Not yet platform-ready:**
- **Rich dashboards** — `DashboardDefinition` decodes; nothing renders. Module home pages fall back to flat lists.
- **POS** — requires Naming, Printing, richer field/control model, Automation runtime, and likely a purpose-built cart surface. None of these are done.
- **Polished ERP-grade control richness** — `FieldType` covers CRUD adequately; it does not cover child-table editing UX, barcode input, image fields, or link search pickers at the level an ERP demands.
- **Fully proven Core → Hub public API sufficiency** — Core is strong enough to start Hub. It is not yet strong enough to claim that all subsystems a production ERP needs are in place and accessible through the public API. That claim becomes true as the missing subsystems in P2.7's gap table are closed.