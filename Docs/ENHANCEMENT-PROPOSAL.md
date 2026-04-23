# Enhancement Proposal

_Last updated: 2026-04-23_

Companion document to [`IMPLEMENTATION-STATUS.md`](./IMPLEMENTATION-STATUS.md). The status doc catalogues _what is_; this doc proposes _what to do next_. Each item is labelled with effort (S/M/L), risk, and the ADR it relates to so the backlog is obvious.

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

Why this was first: every enhancement below lands more safely on top of a test target. The validation pipeline in particular was built for independent stage testing (ADR-022) — shipping it without tests defeats the design.

### P0.2 — Run sync-received writes through `DocumentEngine` [M, medium risk] — ADR-005/022/024 *(done)*

`DocumentEngine.applyRemote(_:from:)` now owns the persistence of sync-received upserts. It runs the same `ValidationPipeline` (ADR-022), submit-immutability guard (ADR-013), and `DocumentVersion` diff recording (ADR-024) that `save(_:)` runs for local writes, while skipping the mutation-log append (the remote mutation is the record) and the optimistic-concurrency check (conflict detection is `ConflictResolver`'s job). `syncState` is forced to `.synced`.

Also fixed an adjacent latent bug: `UpsertPayload` was a 4-field projection that dropped the document's fields on push. Both local saves and remote applies now encode/decode the full `Document` into the mutation payload.

`SyncEngine.applyRemoteUpsert` is now a thin dispatcher: decode → `ConflictResolver` → `.accepted` / `.appendedAsNew` delegate to `applyRemote`; `.conflicted` marks the local row. Coverage landed in `DocumentEngineTests.swift` (`testApplyRemote*`, `testSavedMutationPayloadEncodesFullDocument`) and the new `SyncEngineTests.swift` (StubCloudAdapter, push-payload round-trip, rejected invalid remotes, conflicted-without-overwrite).

**Known follow-up:** `LinkValidationStage` runs on remote writes too, which means out-of-order arrivals (child-before-parent) will be rejected rather than buffered. Assumes the CloudAdapter preserves commit order. When a real adapter lands, either require ordered delivery in the adapter contract or add a buffered-retry layer. Tracked as a candidate ADR.

### P0.3 — Persist `lastServerSequence` [S, low risk] — ADR-005

`SyncEngine.lastServerSequence` is in-memory. After a restart the client re-pulls every remote mutation the adapter chooses to return. Store it in a `sync_state` row (or reuse `schema_version`'s shape) in SQLite and load on startup. The in-file comment already anticipates this.

### P0.4 — Prune `sync_queue` on acknowledgement [S, low risk] — follow-up from ARCHITECTURE-CHANGELOG

Both local `.pushed` and remote `.applied` rows accumulate forever. Add a retention policy:
- Acknowledged local mutations older than N (default 30?) days → delete.
- Applied remote mutations older than the highest persisted `lastServerSequence` → delete.

Done transactionally with vacuum budgeting (don't vacuum on every call). This is the "sync queue pruning" ADR candidate listed in ARCHITECTURE-CHANGELOG; promote it to an ADR as part of the change.

### P0.5 — Align the Permissions doc with the code (or the other way around) [S, medium risk] — ADR-011

Either:
- **A. Fix the doc.** Rewrite §4.4 and ADR-011 to describe the flat `canPerform` / `canAccessField` / `canAccessRow` that actually exists, and remove references to `PermissionEvaluator`, `PermissionDecision`, `AppLevelEvaluator`, `WorkflowLevelEvaluator`.
- **B. Implement the chain.** Introduce the `PermissionEvaluator` protocol, five concrete evaluators, and a chain runner. Replace `PermissionStage` in the pipeline to call the chain.

B is the stated direction (and matches how `ValidationPipeline` is already structured), but it's a larger change. A unblocks P0.2 and P0.8 immediately. **Recommendation: do A now, schedule B.**

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

### P0.8 — `DocumentVersion` stores the full old/new not just a diff summary [S, low risk] — ADR-024

Today `DocumentVersion.fieldDiffs` is computed but there is no reader API. Add:

```swift
public func versions(of documentId: String) throws -> [DocumentVersion]
public func version(of documentId: String, at timestamp: Date) throws -> DocumentVersion?
```

…on `DocumentEngine`. Without a reader, the feature is write-only and gives "complete field-level change history for audit-sensitive documents" (§4.2) no way to be consumed.

### P0.9 — Fix unary minus in `ExpressionEvaluator` [S, low risk] — ADR-017

The tokeniser treats `-` as a negative-number prefix only when `tokens.isEmpty`. `1 + -2` is parsed as `1`, `+`, `2` (silently wrong). Make unary minus a real parser case in `parseFactor` / `parseValue`, or emit `UnaryOp(.neg, ...)` tokens. Minor but easy, and builds the muscle for the AST rework (P2.1).

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

**Effort caveat:** Time-token expansion (`YYYY`, `MM`, `DD`) is trivial; concurrent `.####` increments under offline use need the sync queue to carry the counter update, otherwise two devices both produce `SINV-2026-0001`. A simple answer: prefix series with device ID (`SINV-2026-{deviceId}-0001`) and let the cloud reconcile to a canonical number on first server write. That deserves its own ADR.

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
- `WorkflowGuardStage` — given the current document and its target `docStatus`/status transition, verify the transition is declared in the `WorkflowDefinition` and the user has the role. Rejects the save before any write.
- `PermissionStage` — once P0.5 option B lands, call `PermissionEngine.canPerform(operation: .write, on: docType, userRoles:)`. Until then, wire the existing flat methods.

### P1.6 — Expand `FieldValue` [S, low risk] — ARCHITECTURE-CHANGELOG follow-up

Add `.date(Date)`, `.dateTime(Date)`, `.data(Data)`, `.array([FieldValue])`. Decoder needs a disambiguation key (currently `FieldValue` is likely coded as a tagged enum — confirm during the change). All call sites then switch-exhaust cleanly, which is the biggest argument for doing it: the compiler will flag every coercion / formatter / UI renderer that is currently pretending strings are dates.

### P1.7 — Row-level permissions take a condition expression [M, medium risk] — ADR-011

Today `canAccessRow` is an equality dict. Per the doc ("arbitrary condition filter"), it should accept an expression:
```swift
canAccessRow(document:, userRoles:, rowExpression: String?) -> Bool
```
…evaluated via `ExpressionEvaluator` over the document's fields plus a `user.*` namespace. Lands cleanly after P1.6 and gives real row-level security without writing new code per DocType.

---

## P2 — Structural improvements

### P2.0 — Metadata workspace UX refactor [S, low risk] — ADR-016 / ADR-027 ✅ shipped 2026-04-23

**Rationale:** `DocTypeBuilderView`, `Modules`, and `DocTypes` shared the same workspace chrome but did not read as one coherent family. Section headers (`MercantisSectionHeading`) were visually indistinguishable from interactive chips. Repeated collections (fields, permissions, indexes) were stacked full-form cards — noisy at any count above three.

**Implemented:**

- `MercantisSectionHeading` redesigned as a genuine structural header: uppercase tracking text, no background fill, no border-radius. Looks like a macOS grouped-table section label, not a button.
- `DocTypeBuilderView` restructured into three logical groups:
  - **Basic Info** — compact card for DocType ID, name, module, title field, search fields, flags.
  - **Schema** — segmented tab (`Fields` / `Permissions`). Each collection renders compact single-line summary rows (key · type · Required badge; role · R/W/C/D/S/A matrix). Selecting a row expands an inline editor; other rows stay collapsed. Replaces the previous stacked full-form card-per-item layout.
  - **Configuration** — sync policy card + compact Indexes collection, clearly separated from the schema concerns above.
- `SelectedRecordHeader` given a surface background and bottom divider, making it a proper workspace entity banner. Shared by both Modules and DocTypes detail views.
- `moduleSelectedRecordHeader` (NavigationShell) enriched with a `subtitle` ("Custom Module" / "System Module") and a DocType count badge derived from existing `tooling.navigableDocTypes`. No invented analytics.
- External padding removed from `RecordCollectionHostView`'s `detailHeader` slot to avoid double-padding now that `SelectedRecordHeader` carries its own padding.

**Non-goals respected:** no nav model change, no design-lab promotion, no fake dashboards, no extra color, FormBuilderView left structurally intact.

### P2.0a — Unify record creation as a modal sheet across all entry points [S–M, low risk] — UX ✅ shipped 2026-04-23

**Rationale:** "New" currently does three different things depending on where the user invokes it.

| Entry point | Today | File |
|---|---|---|
| DocTypes workspace → New | `.sheet` presents `DocTypeBuilderView` (correct) | `DocTypeListView.swift:31-34, 60-71` |
| Quick Create → "New Doctype" | `router.openDocType(...)` + pre-loads `activeDocument` in the generic `docTypeDetail` path, bypassing `DocTypeListView` | `NavigationShell.swift:310-317, 364-397` |
| Command Bar → "New <X>" | Same as Quick Create | `NavigationShell.swift:575-588` |
| Generic workspace toolbar → New | `RecordCollectionHostView.handleCreateDocument()` switches to `.detail` view mode and inlines `GenericFormView` | `RecordCollectionHostView.swift:186-194` |

So for `Doctype` specifically — and for every other DocType — whether the user sees a proper modal or an inline-draft-in-the-content-pane depends on *which door they walked through*. This is the opposite of the macOS HIG pattern (Contacts, Reminders, Calendar, Things): "+" always presents a sheet; double-clicking an existing row edits inline.

**Implemented:**

- `CreateRecordSheet` — new sheet primitive (`UIShell/CreateRecordSheet.swift`) that hosts `GenericFormView` on a draft document with a macOS-style header (title "New <DocType.name>", module subtitle), inline error surface, and a Cancel (⎋) / Create (⌘↩) footer. Sheet dismisses on success; the draft is selected in the list via `selectedDocumentID`.
- `RecordCollectionHostView` — `handleCreateDocument` no longer mutates `selectedViewMode`. Instead it sets `createSheetDraft`, which drives a `.sheet(item:)` presenting `CreateRecordSheet`. `onSaveDocument` is now `(Document) throws -> Void` so both the create sheet and the detail-pane Save can surface errors inline (previous code `try?`-swallowed them). A new optional `externalCreateTrigger: Binding<Bool>?` lets the workspace react to router-driven create requests the same way the toolbar "New" does.
- `UIShellRouter` — new `pendingCreate: String?` published property plus `requestCreate(docTypeId:module:)` / `consumePendingCreate(_:)`. `requestCreate` navigates to the workspace responsible for that DocType *before* setting the signal so the workspace is already rendered when it observes it. The `Doctype` built-in is specifically routed through `openDocTypes()` so `DocTypeListView` — not the generic `docTypeDetail` — handles the request; this closes the gap where Quick Create → "New Doctype" previously went through the generic path.
- Quick Create (`NavigationShell.swift`) and Command Bar now call `router.requestCreate(...)` instead of `router.openDocType(...)` + `activeDocument = tooling.createDraftDocument(...)`. No more pre-loaded inline drafts — every "New X" produces the same sheet.
- `DocTypeListView` keeps its bespoke `DocTypeBuilderView` sheet (authoring DocType metadata is not a generic-form task) but now also listens to `router.pendingCreate == BuiltInDocTypes.docType.id` via the same `externalCreateTrigger`. Its `onCreateDocument` continues to return `nil` (short-circuiting the host's generic sheet) and flip `showNewDocTypeSheet = true`, so one trigger path covers both toolbar-invoked and Quick-Create-invoked creation.

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

Currently there are two independent install paths (one via GRDB in the app, one via raw `sqlite3` in `MercantisCLI/Sources/Support/SQLiteDatabase.swift`). They will drift. Extract the mutation-queue-and-metadata-write logic into a shared `AppInstallPlan` struct that both callers execute against their respective database handles, or have the CLI link against the Swift library.

### P2.4 — Dashboard renderer [L, medium risk] — §5.1

`DashboardDefinition` and `DashboardWidget` are declared in `AppRuntimeTypes.swift`. Build a minimal `DashboardView` that renders registered widgets (count, list, number) from `ReportEngine.execute(...)` results. This is what users see first when they open a module.

### P2.5 — List filters / sorting / paging [S, low risk] — §4.15

`DocumentEngine.list(docType:filters:)` is equality-only. Add `sortBy:`, `limit:`, and `where:` (expression) to match the advertised signature. The index definitions in `IndexDefinition` exist but aren't used by the query — this is a good time to translate them into SQLite indexes at install time.

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

The `audit_log` table exists and nothing writes it. Either repurpose it (the sync queue is already acting as the audit log) and drop the table in a v5 migration, or start writing structured `AuditEvent` rows from `DocumentEngine` side-effects. Pick one; the current "write nothing, read nothing" state is pure cruft.

---

## Proposed sequencing

A 4–6 week plan if one engineer is the target:

| Week | Work |
|---|---|
| 1 | P0.1 test target; P0.6 event bus cleanup; P0.7 doc cleanup; P0.9 unary minus. |
| 2 | P0.2 sync-through-engine; P0.3 persisted sequence; P0.4 queue pruning + ADR. |
| 3 | P0.5A (rewrite permissions doc) or P0.5B (implement chain); P0.8 version reader; P1.5 real validation stages. |
| 4 | P1.1 Naming subsystem (behind a feature flag if needed). |
| 5–6 | P1.2 + P1.3 automation runtime + extension-point resolution. |

P1.4 Scheduler, P1.6 FieldValue expansion, and P1.7 row-level expressions slot in as individual PRs alongside the above.

The order matters: testing before refactoring, drift closure before new subsystems, mutation-log soundness before automation that depends on it.

---

## What _not_ to build right now

- **Print & PDF, Files, Cache** — defer. Premature for a platform still closing core loops.
- **WebSocket RealtimeAdapter** — defer until CloudAdapter has a real implementation.
- **More ADRs for existing aspirational features** — the current ADR set already over-describes reality in a few places. Write ADRs when you actually implement (like ADR-023/024 did, which closely track the code).
