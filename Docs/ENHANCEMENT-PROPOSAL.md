# Enhancement Proposal

_Last updated: 2026-04-25 (P2.3 — CLI / app install paths consolidated)_

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

Option A shipped: §4.4 and ADR-011 now describe the flat `PermissionEngine` — `canPerform(operation:on:userRoles:)`, `canAccessField(fieldKey:on:userRoles:operation:)`, `canAccessRow(document:userRoles:rowFilter:)` (later evolved by P1.7 to a `rowExpression`) — that actually exists, and references to `PermissionEvaluator`, `PermissionDecision`, and the evaluator chain have been removed (or reframed as "not shipped" historical notes) from:

- `ARCHITECTURE.md` §3 (architecture diagram), §4.2 (ValidationPipeline `PermissionStage`), §4.4 (Permissions Engine — fully rewritten), §4.12 (Layer 3 extension protocols), §4.15 (Public API Surface), §7 (directory tree).
- `Docs/ADR/ADR-011-multi-level-permission-model.md` — rewritten to describe the shipped flat surface and its out-of-scope checks (app / module gating; workflow-level role checks remain inside `WorkflowEngine`).
- `Docs/ADR/ADR-025-automation-action-registry.md` — the "consistent with `PermissionEvaluator`" line reframed.
- `Docs/ADR/ADR-026-three-layer-extensibility-model.md` — removed `PermissionEvaluator` from the Layer 3 list; added a note that reintroducing it requires implementing the chain first.
- `Docs/IMPLEMENTATION-STATUS.md` §1, §2.4, §5 — removed "shape doesn't match" entries; §2.4 now reads as a regular Shipped / Partial breakdown.

Option B (implement the chain — introduce a `PermissionEvaluator` protocol, five concrete evaluators, and a chain runner; replace `PermissionStage` to call the chain) remains the stated long-term direction, scheduled alongside:
- ~~**P1.7** — row-level expression support (`canAccessRow` predicate via `ExpressionEvaluator`).~~ ✅ shipped 2026-04-25 — see P1.7.
- **App-/module-level gating** — not yet in the engine; a future ADR.

Until then, §4.4 / ADR-011 accurately document what ships.

### P0.6 — Resolve `EventBus` / `EventEmitter` duality [S, low risk] — ADR-020 *(done)*

`EventBus.swift` is gone; `EventEmitter(legacyBus:)` and the bridge are gone; `DocumentEngine.init` / `WorkflowEngine.init` no longer take an `eventBus` parameter. ADR-012's "superseded" status now matches the code.

### P0.7 — Update ARCHITECTURE.md §7 directory tree [S, zero risk] — doc hygiene *(done — 2026-04-26)*

The §7 directory tree is now an accurate reflection of disk: `Automation/`, `Naming/`, and `Scheduling/` (all shipped via P1.1 / P1.2 / P1.4) are listed as on-disk subsystems; `Cache/`, `Files/`, `ImportExport/`, and `Printing/` (P3.1 / P3.2 / P3.3 / P3.4) are listed in the trailing "Planned, not on disk" block with their ADR / proposal references; `Views/DesignSystem/` is in the tree with its "demo-only" caveat. The `DocumentEngine.list` and `PermissionEngine.canPerform` signatures in §4.15 were already updated through P2.5 / P0.5 — `list(docType:filters:whereExpression:sortBy:limit:offset:)` and `canPerform(operation:on:userRoles:)` are now the canonical forms quoted there.

Three additional drift fixes landed in the same pass:

- **§3 architecture diagram** — UIShell is no longer marked `(planned)` (it ships); `ReportEngine (planned)` is no longer marked planned (it ships); `CacheManager` was removed from the Storage box (no `Cache/` subsystem on disk); `FileManager` and `ImportExport` are now explicitly marked `(planned)`.
- **§4.14 Caching Layer** — Reframed to show the `Cache/` location as planned (P3.4) and to enumerate the per-subsystem caches that actually ship today: `MetadataRegistry`'s in-memory cache, `MetaComposer`'s `ResolvedMeta` cache (ADR-021), the `ExpressionEvaluator` parse-cache LRU (P2.1), and `CachingDocumentLookupResolver` (P2.2 / ADR-029). The standalone `CacheManager` API (`getOrCache(...)`, opt-in result caching) is correctly marked deferred until profiling identifies a hot path.
- **§4.15 Public API Surface** — Removed the stale "AutomationActionRegistry is planned" line; added the `AutomationActionRegistry` (P1.2 / ADR-025), `AutomationRunner` (P1.2), `SchedulerService` (P1.4), and `NamingService` (P1.1 / ADR-014) entries that were missing.

(Already done in earlier changesets: ADR-027 added to §8.)

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

### P0.9 — Fix unary minus in `ExpressionEvaluator` [S, low risk] — ADR-017 *(done)*

`-` is now always an operator at the lexer level; `parseFactor` (arithmetic) and `parseValue` (comparison) handle unary `+` / `-` prefixes. `ExpressionEvaluatorTests` covers `1 + -2 == -1` and `3 * -2 == -6`.

---

## P1 — Close the obvious feature gaps

These are features the docs promise and apps will reasonably assume exist.

### P1.1 — Implement the Naming subsystem [M, low risk] — ADR-014 / §4.11 *(done — 2026-04-23)*

`mercantis core/Naming/` ships the five built-in strategies from ADR-014 plus the `NamingService` registry:

```
mercantis core/Naming/
├── NamingStrategy.swift         // protocol + NamingContext + NamingError
├── NamingService.swift          // registry + token parser (splits "naming_series:PATTERN")
├── UUIDv7Strategy.swift         // RFC 9562 default, offline-safe
├── NamingSeriesStrategy.swift   // SINV-.YYYY.-.####, date tokens YYYY/YY/MM/DD, counter in naming_counters
├── FieldDerivedStrategy.swift   // field:email
├── PromptStrategy.swift         // prompt — throws if no caller-supplied name
└── FormatStrategy.swift         // format:{customer}-{year}
```

`DocumentEngine.save` now takes an optional `userSuppliedName:` and returns `@discardableResult Document` so callers can observe the resolved ID. When `document.id` is empty, `NamingService.resolve(...)` runs before the validation pipeline. Migration v5 adds `naming_counters(seriesKey, value)`; the `DocumentEngine` reserves the next counter in its own short write transaction so concurrent saves serialise correctly.

`NamingSeriesStrategy`'s counter namespace is `"<DocTypeId>::<expanded-prefix>"` — prefixes with date tokens reset naturally when the expanded prefix rolls over (new year / month / day). Coverage in `NamingTests.swift` (25 tests) exercises each strategy in isolation, `NamingService` dispatch, and end-to-end through `DocumentEngine.save` including the counter-gap-on-validation-failure contract.

**Known follow-ups (not scoped to P1.1):**
- `DocumentNamingRule` conditional selector (priority-ordered rules that pick strategies based on field values) is not yet implemented.
- Offline multi-device counter reconciliation via the sync queue is not implemented — ADR-014 calls out per-device range reservation; today two devices saving offline will both start at `SINV-2026-0001`.
- `amend` still allocates a raw UUID for the new draft rather than routing through `NamingService`. Reasonable for now; worth revisiting if amended copies need series IDs.

### P1.2 — Implement the Automation runtime [L, medium risk] — ADR-019 / ADR-025 *(done — 2026-04-24)*

`mercantis core/Automation/` ships the P1.2 runtime described below. Handlers
use the registry-based dispatch required by ADR-025; new action types are
added by registering an `AutomationActionHandler` conformance compiled into
Core (downloaded apps cannot).

```
mercantis core/Automation/
├── AutomationActionHandler.swift       // protocol: actionType + execute(document:parameters:context:), AutomationContext, AutomationActionError
├── AutomationActionRegistry.swift      // register / unregister / handler(for:) / execute(...); replaces earlier entries on duplicate register
├── BuiltInActionHandlers.swift         // SetValueHandler, SetStatusHandler, SendNotificationHandler, ValidateHandler, AssignHandler; FieldValueDecoder + ParameterInterpolator helpers
├── AutomationSinks.swift               // NotificationLogWriter / AssignmentLogWriter protocols + in-memory defaults (log-only, no migration)
├── AutomationRunner.swift              // subscribes to DocumentSavedEvent / DocumentSubmittedEvent / DocumentCancelledEvent; matches AppManifest.automationRules; re-entrancy guard on document id
└── AutomationActionDispatcher.swift    // fills the P1.3 ExtensionActionDispatcher seam so manifest-declared documentEventSubscriptions route through the same registry
```

`AppInstaller` now takes an optional `automationRunner:` parameter and, on
`install` / `uninstall` / `restoreExtensionPoints`, registers or releases the
manifest's `automationRules` alongside the P1.3 extension-point bindings.
`DocumentEngine` gains an `AutomationDocumentGateway` conformance (via a thin
extension) so the runner and dispatcher can reload the canonical document
before running handlers and write the mutation back post-commit.

The built-ins map to ADR-025's action-type table:

- `set_value` — writes one field; `FieldValueDecoder` infers the `FieldValue` case from the string literal (or honours an explicit `type` parameter: `string | int | double | bool | null`).
- `set_status` — writes `document.status`. Does not touch ADR-013's `docStatus`; that remains the job of `DocumentEngine.submit` / `cancel` / `amend`.
- `send_notification` — writes one `NotificationLogEntry` to the injected `NotificationLogWriter`. `subject` / `body` support `{field}` placeholders expanded from the document's field map.
- `validate` — evaluates a boolean expression via `ExpressionEvaluator` and throws `AutomationActionError.validationFailed` when the condition is false. Intended to block saves when run inside the save transaction; post-commit it surfaces the failure to the runner / dispatcher's error reporter.
- `assign` — writes one `AssignmentLogEntry` (user or role target) to the injected `AssignmentLogWriter`.

Coverage in `AutomationTests.swift` (25 tests): each handler's happy-path and
missing-parameter branches, the registry's unknown-action-type guard and
handler-replacement semantics, `FieldValueDecoder`'s inference table,
`ParameterInterpolator`'s placeholder handling, the runner's condition
evaluation and Frappe-style `on_update` / `on_change` / `onSave` alias
matching, the re-entrancy guard that breaks `set_value`-rewrites-save loops,
the on-submit-only dispatch path, `AppInstaller` → runner register/unregister
wiring, end-to-end dispatch through `ExtensionPointResolver` via
`AutomationActionDispatcher`, and scheduler-origin placeholder dispatch.

**Known follow-ups (not scoped to P1.2):**
- Pre-commit blocking `validate` — ADR-019 calls for the automation runtime
  to execute inside the save transaction so a failing action rolls back the
  write. That requires threading the runner through
  `DocumentEngine.save(_:)` (new parameter + new coverage), which is deferred
  beyond P1.2. Post-commit `validate` still runs; it reports the failure via
  `RunnerError.ruleFailed` but the commit is not rolled back.
- Persistent `notification_log` / `assignment_log` tables — handlers write to
  in-memory sinks today. Adding migrations before P1.4 (Scheduler) can drive
  real notification delivery would be premature.
- Scheduler-triggered rules — `AppManifest.automationRules` with
  `triggerEvent == "onSchedule"` are registered but never fire. P1.4's
  `SchedulerService` will drive them.
- `AutomationActionDispatcher` running scheduler-origin actions against a
  placeholder `Document` is a minimal path; when a real schedule runs, the
  handler set needs a context shape that doesn't pretend there's a document.

### P1.3 — Implement extension-point resolution at install time [M, medium risk] — ADR-015 / ADR-026 *(done — 2026-04-24)*

`AppManifest.extensionPoints: ExtensionPoints` now ships. Manifests declare two
kinds of extension points:

```
mercantis core/AppRuntime/
├── ExtensionPoints.swift            // ExtensionPoints, DocumentEventSubscription,
│                                    // DocumentEventTrigger, SchedulerEventDeclaration,
│                                    // ScheduleInterval, ExtensionActionDeclaration
└── ExtensionPointResolver.swift     // resolver + dispatcher / registrar seams
```

`ExtensionPointResolver.apply(manifest:)` binds every `documentEventSubscription`
to the matching `MercantisEvent` on `EventEmitter` and forwards every
`schedulerEvent` to an `ExtensionSchedulerRegistrar`. Tokens and scheduler
handles are kept in per-app dictionaries; `resolver.clear(appId:)` — called
from `AppInstaller.uninstall` — cancels every handle idempotently. Reinstall
clears prior bindings before rebinding, so upgrades don't accumulate duplicate
subscriptions.

`AppInstaller.restoreExtensionPoints()` walks the `apps` table and reapplies
every stored manifest's extension points on launch, since in-memory
subscriptions don't survive a process restart.

Two protocol seams keep P1.2 and P1.4 out of P1.3's critical path:

- `ExtensionActionDispatcher` — P1.2's `AutomationActionRegistry` will conform.
  Until then, `LoggingExtensionActionDispatcher` records every dispatched
  action on a testable trail so wiring can be verified without handlers.
- `ExtensionSchedulerRegistrar` — P1.4's `SchedulerService` will conform.
  Until then, `RecordingExtensionSchedulerRegistrar` records declarations
  without arming a timer.

`DocumentEventTrigger` is a closed enum with raw values `on_save`, `on_update`,
`on_change`, `on_submit`, `on_cancel`, `on_amend`, `on_trash`, `on_delete`.
Manifests that declare unsupported triggers (e.g. Frappe's `after_insert`) fail
at `AppManifest` JSON decoding time rather than silently binding nothing.

Coverage in `ExtensionPointsTests.swift`:

- `testManifestDecodesWithoutExtensionPointsField` — pre-P1.3 manifests decode to `.empty`.
- `testManifestRejectsUnsupportedTrigger` — `"after_insert"` fails at decode.
- `testInstallAppliesExtensionPointsAndUninstallReleasesThem` — install/uninstall lifecycle.
- `testReinstallIsIdempotent` — rebinding clears prior tokens.
- `testSchedulerDeclarationsRegisterAndReleaseWithApp` — scheduler registrar round-trip.
- `testOnSubmitSubscriptionFiresOnMatchingDocType` — end-to-end dispatch via `DocumentEngine.submit`.
- `testDocTypeSelectorSkipsNonMatchingDocTypes` — selector filtering.
- `testWildcardSelectorMatchesEveryDocType` — `"*"` selector.
- `testUninstallStopsDispatchingEventsForThatApp` — uninstall releases the subscription.
- `testRestoreReappliesBindingsForAlreadyInstalledApps` — process-restart re-bind.

**Known follow-ups (not scoped to P1.3):**
- `documentEventSubscriptions` observe *after*-commit events. Pre-commit
  blocking actions (the `validate` handler shape in ADR-025) require P1.2's
  automation runtime to run inside the save transaction.
- `after_insert` semantics need `DocumentSavedEvent` to carry an "isNew" flag;
  tracked alongside future event refinements.
- The main app (`mercantis_coreApp.swift`) does not yet construct an
  `AppInstaller` or call `restoreExtensionPoints()` at launch; Hub/app-shell
  integration is the consumer for that wiring.

### P1.4 — Implement the Scheduler [M, medium risk] — §4.13 *(done — 2026-04-24)*

`mercantis core/Scheduling/` ships the periodic-task scheduler that fills the
`ExtensionSchedulerRegistrar` seam left by P1.3.

```
mercantis core/Scheduling/
├── ScheduledTask.swift              // key + appId + interval + dispatch + RetryPolicy
├── CronExpression.swift             // dependency-free 5-field cron parser + matcher
├── SchedulerPersistence.swift       // scheduler_state read/write/clear (key-scoped + prefix-scoped)
└── SchedulerService.swift           // ExtensionSchedulerRegistrar conformance + tick loop
```

Migration v6 adds the `scheduler_state(taskKey, lastRunAt)` table. Task keys
are composed as `"<appId>::<declarationId>"` so a manifest-declared
`SchedulerEventDeclaration` lands on a stable identity that survives
reinstall (resolver's `clear(appId:)` cancels the in-memory binding but
deliberately leaves the persisted row alone, so cadence is preserved across
upgrades). Full uninstall calls `SchedulerService.unregister(appId:)` which
wipes every row whose key starts with `"<appId>::"`.

`AppInstaller` now takes an optional `schedulerService:` parameter and calls
`unregister(appId:)` after `extensionResolver?.clear(appId:)` on uninstall.
The resolver path drops in-memory state per task; the new installer step is
the only place that drops persisted state.

`SchedulerService.start()` runs an opt-in `Task` loop that ticks on
`tickInterval` (default 60 s); the first tick fires immediately so a task
that came due while the app was closed catches up on launch instead of
waiting a full interval. Hosts that prefer to drive the scheduler manually
(tests, CLI) call `tick()` directly without `start()`.

The cron parser supports the dependency-free subset called out in the
original P1.4 sketch: `*`, integer, comma-separated lists, inclusive
ranges, and `*/step`. Day-of-week accepts `0`–`7` with both `0` and `7`
binding to Sunday (Vixie-cron compatibility). When both day-of-month and
day-of-week are explicit, the matcher uses the union (Vixie semantics) so
`"0 12 1 * 5"` fires at noon on the 1st of every month *or* every Friday.
`@yearly` / `@daily` aliases are intentionally not supported — the
`ScheduleInterval` enum already exposes `.daily` / `.hourly` / `.weekly`
/ `.monthly` for those cases.

Coverage in `SchedulerTests.swift` (24 tests):
- `CronExpression` — wildcard, exact, comma-list, inclusive range, step
  with wildcard / range, Sunday-as-zero-or-seven, wrong field count,
  out-of-range, inverted range, zero step, non-integer, exact-time match,
  Vixie union semantics, `nextFireDate` advance + roll-to-next-day.
- `SchedulerPersistence` — round-trip, upsert, prefix-scoped clear.
- `SchedulerService` — first-fire on no-`lastRun`, daily / hourly cadence
  throttling, cron cadence per minute, invalid-cron error reporting,
  process-restart preserves `lastRun`, restart fires immediately for
  backlogged tasks, handle cancel stops dispatch, handle cancel preserves
  cadence for reinstall, `unregister(appId:)` wipes persistence,
  `ExtensionSchedulerRegistrar` conformance via the protocol type.
- `MigrationRunnerTests` — extended to assert v6 brings
  `highestAppliedVersion()` to 6 and creates `scheduler_state`.
- End-to-end test routes a manifest-declared scheduler event through
  `AppInstaller.install` → `ExtensionPointResolver` → `SchedulerService` →
  `LoggingExtensionActionDispatcher`, then verifies that
  `installer.uninstall` clears both the in-memory binding and the persisted
  row.

**Known follow-ups (not scoped to P1.4):**
- The main app (`mercantis_coreApp.swift`) still does not construct an
  `AppInstaller` / `SchedulerService` at launch. Hub/app-shell integration
  is the consumer for that wiring.
- Scheduler-triggered automation rules (`AutomationRule.triggerEvent ==
  "onSchedule"`) — P1.2 registers them but never fires. The runner needs
  to register itself as a `ScheduledTask` per matching rule when the
  scheduler is wired to the runner; deferred until host-app wiring lands.
- Background-task budget categories (`short` / `default` / `long` from
  §4.13) and `audit_log` writes for failed runs are not implemented; the
  current loop is a single in-process tick. Sufficient for the cadences
  the manifest exposes today.

### P1.5 — Turn `WorkflowGuardStage` and `PermissionStage` into real stages [S, low risk] — ADR-022 *(done — 2026-04-23)*

Both stages are now real guards in `ValidationPipeline`.

`WorkflowGuardStage` resolves the DocType's `workflowId` via a new `ValidationContext.workflowProvider` closure and compares the document's `status` against the previously-persisted status (obtained via `ValidationContext.previousStatus`). On a detected change, the stage:

- rejects transitions that are not declared in the `WorkflowDefinition` (`from == previous`, `to == document.status`);
- rejects transitions whose `allowedRoles` do not intersect the caller's roles (system / import contexts with empty `userRoles` remain exempt);
- rejects transitions whose `conditionExpression` evaluates to false, and surfaces evaluator errors as structured `DocumentValidationError`s.

Creation (no previously-persisted row) and same-status saves are accepted — neither is a transition. `docStatus` lifecycle moves (submit / cancel / amend) remain governed by ADR-013 and are orthogonal to this stage.

`PermissionStage` now delegates directly to `PermissionEngine.canPerform(operation:on:userRoles:)` (ADR-011's flat surface, per P0.5 option A). `ValidationContext.operation` selects the `DocumentOperation` to check; `DocumentEngine.runValidationPipeline` passes `.create` when the document is new and `.write` otherwise. Empty `userRoles` and empty `docType.permissions` both still short-circuit to a pass, matching the prior convention. When ADR-011 option B lands, this stage will swap the flat call for the evaluator chain without a pipeline-level change.

`DocumentEngine` supplies the new context inputs from the existing SQLite tables (`documents.status` and the `workflows` table). No schema change was required.

Coverage in `ValidationPipelineTests.swift`:

- `testPermissionStagePassesWhenDocTypeDeclaresNoPermissionRules`
- `testPermissionStagePassesWhenUserRolesEmpty`
- `testPermissionStageHonoursCreateOperationDistinctFromWrite`
- `testWorkflowGuardPassesWhenNoWorkflowAttached`
- `testWorkflowGuardPassesWhenWorkflowUnresolvable`
- `testWorkflowGuardPassesOnNewDocumentCreation`
- `testWorkflowGuardPassesWhenStatusUnchanged`
- `testWorkflowGuardRejectsUndeclaredTransition`
- `testWorkflowGuardRejectsUnauthorisedTransition`
- `testWorkflowGuardAllowsDeclaredTransitionWithRole`
- `testWorkflowGuardRejectsTransitionWhenConditionFalse`
- `testWorkflowGuardAllowsTransitionWhenConditionTrue`
- `testWorkflowGuardSkipsRoleCheckForSystemContext`
- `testWorkflowGuardReportsEvaluationErrorForMalformedCondition`

### P1.6 — Expand `FieldValue` [S, low risk] — ARCHITECTURE-CHANGELOG follow-up *(done — 2026-04-24)*

`FieldValue` now has nine cases: the original `.string` / `.int` / `.double` / `.bool` / `.null` primitives plus `.date(Date)`, `.dateTime(Date)`, `.data(Data)`, and `.array([FieldValue])`.

Encoding uses a two-shape wire format. The legacy primitives still encode as untagged JSON (`"abc"`, `42`, `true`, `null`) so existing database rows and sync-queue blobs decode byte-for-byte. The four new cases encode as a tagged envelope:

```json
{ "$type": "date",     "$value": "2026-04-24T10:00:00Z" }
{ "$type": "datetime", "$value": "2026-04-24T10:00:00Z" }
{ "$type": "data",     "$value": "<base64>" }
{ "$type": "array",    "$value": [ <FieldValue>, ... ] }
```

Decoder probes the tagged envelope first (`$type` tag dispatch) and falls back to the untagged primitive path, so a mixed-version dataset decodes without a migration.

Downstream wiring followed the new cases out:

- `TypeCoercionStage.isTypeCompatible` accepts typed `.date` / `.dateTime` for `.date` / `.datetime` fields and still accepts ISO8601 strings for backward compat; `.attachment` fields accept `.string` (id) or inline `.data`.
- `RequiredFieldStage.isValueEmpty` treats typed dates as never empty, `.data` as empty iff the payload has zero bytes, and `.array` as empty iff it has zero elements.
- `ExpressionEvaluator.numericValue` / `fieldValueToExprValue` surface dates as `timeIntervalSince1970`, so expressions like `start < end` work without a dedicated date AST; `.data` / `.array` fall through to `.null` for comparison purposes.
- `ReportEngine.formatValue`, `GenericListView.displayValue`, and `BuiltInActionHandlers.stringify` emit deterministic display strings for every new case instead of returning `nil`.
- `NamingService` strategies: `FormatStrategy` and `FieldDerivedStrategy` now stringify typed dates as ISO8601; `.data` and `.array` are rejected with `NamingError.missingFieldValue` (they are not naming-convertible).
- `FieldValueDecoder` (the `set_value` handler's literal parser) gained `date` / `datetime` / `data` type tags so manifest-declared automation rules can target the typed cases; `array` is deliberately unsupported as a manifest string literal (constructed in code only).
- `GenericFormView.dateBinding` now writes typed `.date` / `.dateTime` on save (based on the field's declared `FieldType`) and reads typed values first, falling back to the ISO8601-string path only for legacy rows.

Coverage in `FieldValueTests.swift` (24 tests): tagged-envelope encode/decode for each new case, untagged primitive round-trip (backward-compat), explicit wire-shape assertion on the `data` envelope, unknown-`$type` rejection, recursive `.array` equality, `TypeCoercionStage` happy-paths and the bool-for-date rejection, `RequiredFieldStage` emptiness matrix for the new cases, `ExpressionEvaluator` ordering typed dates by epoch seconds and treating opaque values as null, `FormatStrategy` / `FieldDerivedStrategy` dispatch on `.date` / `.dateTime` plus rejection of `.data`, and `FieldValueDecoder` parsing `"date"` / `"data"` with a malformed-value rejection.

**Known follow-ups (not scoped to P1.6):**
- `FieldType` does not yet expose a dedicated "array" type or "data" type surface in the form builder; the new `FieldValue` cases are a storage/expression-layer expansion. Rendering new control types is P2.8 work.
- `TypeCoercionStage` allows `.date` ↔ `.dateTime` interchange today (either typed case satisfies either field type). A stricter separation can land once the UI picker treats the two as distinct; keeping them interchangeable now avoids a forced migration for existing rows that used `.string` indiscriminately.

### P1.7 — Row-level permissions take a condition expression [M, medium risk] — ADR-011 *(done — 2026-04-25)*

`PermissionEngine.canAccessRow` now takes a sandboxed boolean `rowExpression` evaluated by `ExpressionEvaluator` (ADR-017) over the document's fields plus a `user.*` namespace. The previous equality-only `[String: FieldValue]` filter was replaced; nothing in the codebase consumed the old signature, so no callers needed migration.

```swift
public func canAccessRow(
    document: Document,
    userRoles: Set<String>,
    rowExpression: String?,
    userId: String = "",
    userAttributes: [String: FieldValue] = [:],
    expressionEvaluator: ExpressionEvaluator = ExpressionEvaluator()
) -> Bool
```

The evaluator sees:
- every entry in `document.fields` at its declared key, and
- a `user.*` namespace populated from `userId` (`user.id`), `userRoles` (`user.roles` as `.array([.string])`, sorted), and any `userAttributes`. Caller-supplied keys without a `user.` prefix are namespaced automatically; entries with the prefix are taken as-is. `userAttributes` overrides the standard entries; any `user.*` key overrides a document field of the same name (so a malicious `user.id` field cannot impersonate the namespace).

A `nil`, empty, or whitespace-only expression grants access. An expression that fails to evaluate — parse error, undefined identifier, type mismatch — fails closed and returns `false`. Common patterns: `"owner == user.id"`, `"warehouse == user.warehouse"`, `"region == user.region && status == \"Submitted\""`. The P1.6 typed `.date` / `.dateTime` cases compare cleanly via the evaluator's epoch-seconds path, so deadline-style filters like `"expires_at > user.now"` work.

Coverage in `PermissionEngineTests.swift` (20 tests): the three nil/empty/whitespace short-circuits, equality and compound expressions over document fields, numeric comparison, typed-date comparison (P1.6 dependency), `owner == user.id` matching, the empty-userId fallback, `userAttributes` namespacing for both prefixed and unprefixed keys, the `userAttributes`-overrides-`user.id` case, the `user.*`-overrides-document-field case (security-critical), three fail-closed paths (undefined identifier returning `.null`, malformed expression with missing RHS, and a typeMismatch throw via unary-minus on a string identifier), plus sanity coverage for `canPerform` (matching / non-matching role) and `canAccessField` (no permission block / restricted block).

**Known follow-ups (not scoped to P1.7):**
- The engine accepts and evaluates an expression but does not decide *which* expression applies for a given (DocType, role, user) tuple. A `DocPerm`-style per-role row filter on metadata, plus `DocumentEngine.list` enforcement of those filters, are downstream.
- `ValidationPipeline`'s `PermissionStage` still only calls `canPerform`. Row-level checks at write time would require threading the row expression through `ValidationContext`.
- Role membership is exposed as a `.array([.string])` for completeness, but the evaluator's comparison rules treat `.array` as `.null`, so `user.roles == "Admin"` is not directly expressible. A `has_role(...)` evaluator function or per-role boolean attributes (e.g. caller passes `userAttributes: ["is_admin": .bool(...)]`) is the workaround until the AST refactor in P2.1 introduces function calls.

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

### P2.1 — Turn the ExpressionEvaluator into a real AST [M, low risk] — ADR-017 *(done — 2026-04-25)*

`ExpressionEngine/` is now a two-phase design that matches the contract `ARCHITECTURE.md` §4.7 has been advertising for some time.

- `ExpressionAST.swift` — typed `ExpressionNode` (`.literal`, `.fieldRef`, `.unary`, `.binary`, `.call`) plus `LiteralValue`, `UnaryOperator`, `BinaryOperator`, and `ExpressionSourceRange`. Every node carries a `[start, end)` UTF-8 byte range over the original source; the lexer that feeds the parser computes those offsets up-front.
- `ExpressionParser.swift` — recursive-descent parser. Grammar runs `or → and → equality → comparison → additive → multiplicative → unary → call → primary`, which is strictly more powerful than the legacy two-grammar split (`parseValue` for booleans, `parseFactor` for arithmetic). Comparison RHS now accepts arithmetic (`total > 100 + 50`); trailing tokens (`a == b c`) and unknown characters (`a $ b`) raise `ExpressionParseError` instead of being silently dropped. The `.call` form is parsed but rejected by the interpreter so the AST shape is forward-compatible with P2.2's `lookup()`.
- `ExpressionEvaluator.swift` — public façade. The legacy `evaluateBool(expression:context:)` / `evaluateFormula(expression:context:)` API is unchanged; new call sites that evaluate the same source repeatedly (a `whereExpression` over many rows; an automation rule's `conditionExpression` per save) can call `parse(_:)` once and pass the resulting `ExpressionNode` to the new `evaluateBool(parsed:context:)` / `evaluateFormula(parsed:context:)` overloads.

The three "immediate wins" the proposal called out all landed:

- **Static field-reference analysis** — `ExpressionEvaluator.referencedFields(in:)` returns the set of identifiers an expression touches without evaluating it. `SchemaValidator.validate(_:)` now uses this to reject any DocType whose `visibilityExpression` / `readOnlyExpression` / `formulaExpression` references a field key the DocType does not declare. Two new `ValidationError` cases — `unknownFieldInExpression` and `expressionParseFailed` — surface this at install time instead of at first form render. Dotted identifiers (`user.id`, `user.roles`) are exempt from the declared-field check because the permission engine pre-flattens them into the evaluation context. A `validatesExpressions` flag on `SchemaValidator` lets builder previews opt out while a draft DocType is incomplete.
- **Parsed-expression cache** — the evaluator keeps a bounded LRU (`parseCacheLimit`, default 256) of recently-parsed source strings keyed by raw text. `evaluateBool(expression:context:)` looks up or parses, then walks; calling it with the same expression twice parses once. The cache is thread-safe via `NSLock`; `parseCacheLimit: 0` disables it.
- **Constant folding** — pure-literal subtrees collapse at parse time. `2 + 3 * 4` materialises as a single `.literal(.number(14))`; `status == "Submitted" || true` collapses to `.literal(.bool(true))`. Subtrees that throw at fold time (e.g. division by zero) are deliberately left unfolded so the runtime error contract is preserved (`testConstantFoldingPreservesDivisionByZeroAsRuntimeError`).

**Caret-style errors** — parse failures lift through a new `EvaluatorError.parseError(ExpressionParseError)` case. `ExpressionParseError.description` renders the message, the source line, and a `^` pointer at the byte offset. The legacy `EvaluatorError.unexpectedToken` case is preserved for callers that match on it (`DocumentEngine.list` `whereExpression` fail-closed regression, `ValidateHandler.expressionFailed` wrapping); other parse errors lift through `.parseError`.

**Backward-compatibility** — the existing legacy contracts are preserved verbatim:

- `evaluateBool` empty-string short-circuits to `false` (`testEmptyExpressionEvaluatesToFalse`).
- Truthiness fallback for bare identifiers (`flag` resolves to `.bool(true)` in the context).
- Undefined fields throw `undefinedField` from arithmetic context, but resolve to a comparison-only `.null`-like value from boolean context. The interpreter carries an internal `.undefined(name)` runtime value — arithmetic operators detect it and throw, comparisons treat it like `.null`, truthiness yields `false`. `testUndefinedFieldInFormulaThrows` still throws; `testIdentifierTruthiness` for `missing` still returns `false`.
- Date / dateTime fields compare and order as epoch seconds (`testExpressionEvaluatorComparesDatesAsEpochSeconds`); `.data` / `.array` map to `.null` (`testExpressionEvaluatorTreatsOpaqueValuesAsNullForComparison`).
- The `unary minus` regression (P0.9) tests still pass — unary `-` / `+` / `!` bind tighter than every binary operator and walk the same RuntimeValue path.

**Coverage in `ExpressionEvaluatorTests.swift`** — every legacy test (15) is preserved. New tests exercise: `parse` round-trip + `evaluateBool(parsed:)`, parse-cache equality, `referencedFields(in:)` for compound / literal-only / dotted / empty expressions, constant-folding collapse vs preservation of fieldRef-bearing trees, division-by-zero deferral, source-position parse errors (unknown character, unterminated string, trailing tokens), `parseCacheLimit: 0` opt-out.

**Coverage in `SchemaValidatorTests.swift` (new)** — declared-field happy path / undeclared-field rejection for each of the three field-level expression slots, malformed-expression rejection (`expressionParseFailed`), dotted-identifier exemption, `validatesExpressions = false` opt-out.

**Known follow-ups (not scoped to P2.1):**

- Workflow `transition.conditionExpression` and `AutomationRule.conditionExpression` are not yet validated at install time. Both reference DocType fields and would benefit from the same `referencedFields` check; the wire-up belongs in `AppInstaller.install` rather than `SchemaValidator` (the rules don't live on the DocType). Filed for a future pass.
- The new parser elevates `+`-then-arithmetic on the RHS of a comparison (`total > 100 + 50`) from "silent drop" to "actually computed". Any production manifest that was relying on the legacy drop will now see the comparison evaluate against the full RHS — this is a strict improvement, but worth flagging.
- Constant folding is conservative — it never folds `||` / `&&` when one side is constant and the other isn't (e.g. `true || x`). Adding short-circuit folding is a safe future tweak.
- `IndexDefinition`-driven `whereExpression` push-down to SQL still requires the AST → SQL emitter that P2.5 deferred; the parser side of that work is now in place.

### P2.2 — Cross-document `lookup(docType, name, field)` [M, medium risk] — ADR-029 *(done — 2026-04-25)*

The sandboxed expression engine (ADR-017) now recognises one named call: `lookup(docType, name, field)`. Shape and semantics are documented in [ADR-029](ADR/ADR-029-cross-document-lookup.md); the short version:

- `docType` and `field` must evaluate to non-empty strings (idiomatically string literals); `name` may evaluate to a string, `null`, or an undefined identifier (a missing/null name short-circuits to `null`, so `lookup("Item", optional_link, "rate")` is safe on draft documents).
- A successful lookup returns the resolved field's `FieldValue`, mapped through the existing `fieldValueToRuntime` path so typed dates compare as epoch seconds and opaque values land as `.null`. A missing document or missing field both resolve to `.null`.
- A `nil` resolver makes every call throw `unexpectedToken("call to 'lookup' is not supported in this evaluator")` — opt-in, not silent.
- Wrong arity / non-string args throw typed errors; resolver throws are caught and surfaced as `.null` so transient I/O can't crash a form's expression evaluation.
- A per-evaluation `lookupBudget` (default 32) caps the number of `lookup(...)` calls a single top-level evaluation may make; excess calls throw `EvaluatorError.lookupBudgetExceeded(limit:)`. Sets the ADR-008 sandbox posture for the new I/O capability.

Resolver injection is a new `DocumentLookupResolver: AnyObject` protocol (`mercantis core/ExpressionEngine/DocumentLookupResolver.swift`). `DocumentEngine` is the reference resolver — conformance is via an extension that calls `fetch(docType:id:)`, so permission / soft-delete / index behaviour stays consistent with every other read.

`CachingDocumentLookupResolver` is the read-through cache the proposal called for ("cache-by-read with per-save invalidation, already how `MetaComposer` works"):

- Memoizes successful and absent reads in `[CacheKey: [String: FieldValue?]]` keyed by `(docType, name)`. The inner `FieldValue?` preserves the distinction between "looked up and the field is absent" and "never looked up".
- Constructed with an `EventEmitter`, subscribes to `DocumentSavedEvent` / `DocumentDeletedEvent` / `DocumentSubmittedEvent` / `DocumentCancelledEvent` and drops the cache entry for `(docType, id)` on each. `DocumentAmendedEvent` is intentionally ignored — amends mint a new id with no entries to drop and leave the original unchanged.
- Cross-device invalidation is implicit: a remote write that arrives via `SyncEngine` lands through `DocumentEngine.applyRemote(_:from:)` (P0.2), which fires the same `DocumentSavedEvent`.
- Holds `base` weakly so engine-owns-cache-owns-engine ownership doesn't form a retain cycle.

`DocumentEngine` exposes two new lazy public properties — `lookupCache: CachingDocumentLookupResolver` and `listExpressionEvaluator: ExpressionEvaluator` (pre-wired with the cache) — so callers can share the same parse cache and lookup cache across automation, list filtering, and form-level visibility expressions. `DocumentEngine.list`'s `whereExpression` now uses `listExpressionEvaluator`, so list filters can call `lookup(...)` and the join is memoized once per parent across the row scan.

Coverage in `DocumentLookupResolverTests.swift` (24 tests):

- Evaluator: lookup with concrete value / missing document / missing field / null name / undefined name / empty-string name; resolver-not-injected throws; wrong arity throws; non-string docType / field throws; resolver throw treated as null; unknown call name throws.
- Lookup budget: budget-exceeded throws after the configured number of calls in one evaluation; `lookupBudget: 0` disables lookup entirely; budget is per-evaluation, not per-evaluator (refilled on every top-level call).
- `CachingDocumentLookupResolver`: read-through hits base exactly once per `(docType, name, field)`; misses are cached as absence; field-key scoping; manual `invalidate(...)` / `clear()`; per-event invalidation for `DocumentSavedEvent` / `DocumentDeletedEvent` / `DocumentSubmittedEvent` / `DocumentCancelledEvent`; unrelated keys survive.
- End-to-end via `DocumentEngine`: engine conformance to `DocumentLookupResolver`; `list(whereExpression:)` correctly filters via `lookup(...)` against parent-document fields; engine save fires `DocumentSavedEvent` and the engine's own `lookupCache` invalidates the affected entry.

`ADR-017` was updated to reference ADR-029 for the new call form. The ADR README index was extended with ADR-029.

**Known follow-ups (not scoped to P2.2):**
- Static `referencedFields(in:)` analysis sees the `name` argument as a referenced field of the *current* DocType but does not record that the expression also reads `(docType, field)` from another DocType. A future enhancement could surface those cross-DocType dependencies for install-time validation.
- The cache is unbounded today. Adding an LRU bound is a future tweak gated on real measurement; typical write patterns keep the working set small.
- A second named call (e.g. a `has_role(...)` predicate to round out P1.7's role-membership story) is now a one-case extension to `evaluateCall`. The AST shape is forward-compatible.

### P2.3 — Consolidate `AppInstaller` and CLI `install-app` [M, medium risk] — CLI/app parity *(done — 2026-04-25)*

The CLI now imports `MercantisCore` (the library product P2.6 shipped) and runs the same `AppInstaller` pipeline the app does. Both surfaces share one schema, one `SchemaValidator` pass, one set of side-effects (DocType + field registration, expression-index reconciliation, sync-queue mutation, extension-point binding).

**Engine surface added (`mercantis core/AppRuntime/AppInstaller.swift`):**

```swift
public static func decodeManifest(from data: Data) throws -> AppManifest
public func validate(manifestData: Data) throws -> AppManifest        // dry-run
@discardableResult
public func install(manifestData: Data) throws -> AppManifest         // decode + install
```

`AppInstallerError` gained a `.manifestDecodeFailed(underlying:)` case so the CLI can distinguish a malformed JSON file from a downstream install error.

**CLI changes (`MercantisCLI/Sources/Commands/`):**

- `InstallApp.swift` — opens the database via `MercantisDatabase` (so Core's migrations run), constructs an `AppInstaller` with a fresh `MetadataRegistry`, and dispatches to `validate(manifestData:)` (`--dry-run`) or `install(manifestData:)`. The pre-decode envelope checks (reverse-DNS id, semver `version` / `minimumCoreVersion`) stay on the CLI side as a fast-fail layer that runs before JSON decode.
- `ListApps.swift` — opens via `MercantisDatabase` and reads the canonical `apps(id, name, version, installedAt, payload)` schema directly through GRDB. The legacy `(title, manifestJson)` column-rename branch is gone; the dual-shape table is no longer possible because both install paths produce the same schema.
- `NewApp.swift` — scaffolds a canonical `AppManifest` (uses Core's `Codable` shape) so a fresh scaffold can be installed end-to-end. The earlier `AppManifestTemplate` private struct (with non-canonical `title` / `publisher` / `fixtures` / `schedulerEvents` keys) is gone.
- `NewDocType.swift` — encodes a canonical `DocType` directly. Drops the legacy `namingSeries` / `namingField` / `namingFormat` keys (the strategy + arg are already encoded in `autoname`); validation now goes through Core's `SchemaValidator` with `validatesExpressions = false` (the scaffold has no expressions yet, but the install path will catch undeclared references at install time per P2.1).

**Package wiring (`Package.swift`)** — the CLI executable target now depends on `MercantisCore`. The CLI keeps its `SQLite3` system-library link for `Migrate` / `CreatePatch` / `RunPatch`, which operate on raw SQL patch files rather than the engine schema; consolidating those onto `MercantisCore` is not needed and not in scope.

**Lenient `FieldDefinition` decode** — `mercantis core/Metadata/FieldDefinition.swift` gained a custom `init(from:)` that treats `section` / `column` / `collapsible` / `validationRules` / `isSearchable` / `isSynced` / `allowOnSubmit` as optional with sensible defaults. Hand-authored manifests and the CLI scaffold (which omits the layout fields) now decode without forcing every JSON file to spell out every key.

**Coverage in `CLIInstallParityTests.swift`:**

- `testDecodeManifestFromJSONRoundTripsAllFields` — engine-encoded JSON survives a `decodeManifest` round-trip.
- `testDecodeManifestSurfacesDecodeFailureAsTypedError` — malformed JSON ⇒ `AppInstallerError.manifestDecodeFailed`.
- `testValidateManifestDataReturnsManifestWithoutWriting` — dry-run path leaves `apps` and `doctypes` empty.
- `testValidateManifestDataRejectsInvalidDocType` — `SchemaValidator` short-circuits dry-run validation.
- `testInstallFromManifestDataMatchesDirectInstallEndState` — two parallel databases (CLI-via-data + app-via-`install(_:)`) produce identical end state: same `apps` row shape, same registered DocType + fields, same `sync_queue.installApp` mutation enqueued.
- `testInstallFromManifestDataCreatesExpressionIndex` — declared `IndexDefinition` rows materialise as SQLite expression indexes when installed via the JSON path (closes the P2.5 follow-up).
- `testFieldDefinitionDecodesWithoutLayoutFields` / `testFieldDefinitionDecodesWithLegacyAndNewKeysMixed` — pin the lenient decoder.

**Known follow-ups (not scoped to P2.3):**
- Legacy CLI databases (created by `mercantis install-app` *before* P2.3) had a non-canonical `apps(id, title, version, installedAt, manifestJson)` schema and stored a manifest blob without registering DocTypes / workflows / sync state. They are not migrated automatically — recreate the database. No production state is lost because the legacy install never wired up the engine's metadata tables.
- `Migrate` / `CreatePatch` / `RunPatch` still use the CLI's `SQLiteDatabase` raw-SQL helper. They operate on `patch_log` and arbitrary SQL deltas, not the engine schema, so consolidation onto `MercantisCore` would only swap the SQLite client without changing semantics. Deferred until a concrete need arises.
- The CLI's `SchemaValidator` opt-in for expression checks is `false` in `new-doctype`. When a richer scaffold gains expression slots, flipping it to `true` (or running it inside the install pass) catches undeclared references earlier.

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

### P2.5 — List filters / sorting / paging [S, low risk] — §4.15 *(done — 2026-04-25)*

`DocumentEngine.list` now exposes the full surface §4.15 used to caveat as planned:

```swift
public func list(
    docType: String,
    filters: [String: FieldValue]? = nil,
    whereExpression: String? = nil,
    sortBy: [ListSort]? = nil,
    limit: Int? = nil,
    offset: Int = 0
) throws -> [Document]
```

Three orthogonal additions ride on the existing equality-filter behaviour:

- **`whereExpression`** — a sandboxed boolean expression evaluated per row via `ExpressionEvaluator.evaluateBool` (ADR-017). Empty / whitespace expressions are ignored; evaluation failures fail closed (the row is excluded), matching the convention `PermissionEngine.canAccessRow` (P1.7) established. Lets callers express predicates the equality-filter map can't (`amount > 1000`, `status == "Submitted" && warehouse == "Main"`, P1.6 typed-date comparisons via the evaluator's epoch-seconds path).
- **`sortBy`** — ordered `[ListSort]` chain. `ListSort` is a new public struct (`fieldKey: String`, `direction: .ascending | .descending`). Sort keys may name either a `documents`-table system column or a user-defined field; the comparator handles missing values (sorted last in ascending order), numeric cases (int / double / bool / date-as-epoch), and strings.
- **`limit` / `offset`** — paging. `limit == nil` means "to end"; `offset` is bounds-clamped so out-of-range values yield `[]` rather than crashing.

The new `IndexDefinition` use is the second half of P2.5: declared indexes now actually accelerate queries.

- `MetadataRegistry.register(_:)` reconciles SQLite expression indexes for every `DocType.indexes` entry, creating `CREATE INDEX … ON documents(doctype, json_extract(payload, '$.<fieldKey>'))` and dropping any prior indexes whose name shares the DocType's `idx_doc_<sanitized-doctype>_` prefix but no longer matches a current `IndexDefinition`. Re-registering a DocType is idempotent.
- `DocumentEngine.list` pushes filters and sort keys to SQL when the field is either a system column or a declared `IndexDefinition`. Other filters / sorts run in memory after the row fetch. Paging is pushed to SQL only when no in-memory filtering or sorting is required; otherwise it runs in memory after those passes so the slice is taken from the final ordered list.

**Downstream wiring** — three existing call sites kept their original signatures untouched (every new parameter has a default): `ReportEngine.execute`, `DocumentEngine.runValidationPipeline`'s `UniqueConstraintStage` callback, and `DocTypeToolingContext.listDocuments`.

**Doc updates** — `ARCHITECTURE.md` §4.6 (Document Engine method list) and §4.15 (Public API Surface) now show the full signature; the "sort/limit planned" caveat is gone.

**Tagged `FieldValue` cases (`.date`, `.dateTime`, `.data`, `.array`)** — these encode as `{"$type":...,"$value":...}` envelopes (P1.6) and would not match a flat `json_extract` value, so equality filters carrying tagged values transparently fall back to in-memory comparison. Sorts on tagged-date fields work in-memory via the comparator's epoch-seconds path; sorts on `.data` / `.array` fall through to the string fallback.

**Coverage in `DocumentEngineTests.swift`** — 17 new tests exercise: empty / equality filters, mixed system + indexed-field filter pushdown, in-memory filter fallback for non-indexed fields, `.null` filter via `IS NULL`, ascending / descending sort on system columns and indexed fields, multi-key sort with mixed direction, in-memory sort when one key is non-indexed, missing-value sort placement, `whereExpression` filtering with comparison and compound operators, fail-closed behaviour on parse error and undefined identifier, empty / whitespace expression short-circuits, `limit` only, `offset` only, `limit + offset`, out-of-range offset, and the existing-callers regression (default-args call signature unchanged). `MigrationRunnerTests` was extended to assert that an `IndexDefinition`-backed DocType registration creates the matching `idx_doc_*` row in `sqlite_master`, and that re-registering with the index removed drops the row.

**Known follow-ups (not scoped to P2.5):**
- Range / inequality predicates on indexed fields aren't pushed to SQL today — only equality is. The indexes still help at the in-memory `whereExpression` stage because the SQL pre-filter narrows the row set first; lifting the where expression itself into SQL is P2.1 territory (parser → AST → SQL emitter).
- `IndexDefinition.unique == true` is still enforced only by `UniqueConstraintStage`, not by a SQLite `UNIQUE` index. Adding the SQLite-level guarantee would catch race conditions but change error semantics from `DocumentValidationError` to a SQLite constraint violation; deferred until the trade-off is genuinely needed.
- ~~The CLI's raw-`sqlite3` install path (P2.3) does not create expression indexes today — when CLI install is consolidated onto Core, it inherits the new behaviour for free.~~ ✅ shipped 2026-04-25 — see P2.3.

### P2.6 — Productize Core as a reusable library target [M, low risk] — ADR-007 *(done — 2026-04-25)*

`Package.swift` now declares a `.library(name: "MercantisCore", targets: ["MercantisCore"])` product alongside the existing `mercantis` executable. Hub — or any third-party app — can pull Core in with a standard `.package(url:from:)` dependency and `import MercantisCore`.

```swift
products: [
    .library(name: "MercantisCore", targets: ["MercantisCore"]),
    .executable(name: "mercantis", targets: ["mercantis"])
]
```

The `MercantisCore` target points at the existing `mercantis core/` directory with `exclude:` for the four UI / app-shell entries (`Assets.xcassets`, `mercantis_coreApp.swift`, `UIShell/`, `Views/`). Engine subsystems — `AppRuntime/`, `Automation/`, `Customization/`, `DocumentEngine/`, `ExpressionEngine/`, `Metadata/`, `Naming/`, `Notifications/`, `Permissions/`, `Reporting/`, `Scheduling/`, `Storage/`, `SyncEngine/`, `Workflows/` (51 source files) — compile into the library; SwiftUI views and the App entry stay in the Xcode app target. GRDB is added as a SwiftPM dependency (`https://github.com/groue/GRDB.swift`, `from: "6.0.0"`) and threaded through the library target only — the CLI continues to use its `MercantisCLI/SQLite3` system-library path (consolidating the two persistence stacks is P2.3).

Access-modifier audit: every top-level engine type (`DocumentEngine`, `MercantisDatabase`, `SyncEngine`, `WorkflowEngine`, `MetaComposer`, `MetadataRegistry`, `PermissionEngine`, `ValidationPipeline`, `ExpressionEvaluator`, `ReportEngine`, `AppInstaller`, `AutomationActionRegistry`, `AutomationRunner`, `SchedulerService`, `EventEmitter`, `NamingService`, `ConflictResolver`, …) is declared `public` with `public init`s and `public func`s. Manifest / DocType value types (`Document`, `DocType`, `FieldDefinition`, `FieldValue`, `PermissionRule`, `IndexDefinition`, `ResolvedMeta`, `MutationRecord`, `WorkflowDefinition`, …) expose `public let` / `public var` members. Two helpers in `Automation/BuiltInActionHandlers.swift` (`FieldValueDecoder`, `ParameterInterpolator`) are deliberately internal — they're implementation detail of the built-in action handlers. No engine source file imports SwiftUI / AppKit / UIKit; the boundary is one-way (UI → engine).

ADR-007's "public/internal boundary in Core is enforced by the Swift module system" consequence is now true at the SwiftPM target level.

**Known follow-ups (not scoped to P2.6):**
- The Xcode app target (`mercantis core`) still compiles the engine source directly (via project membership). Migrating it to consume the `MercantisCore` SwiftPM product instead — so the Xcode-side build path also enforces the module boundary — is a `.pbxproj` change best done in Xcode itself: remove engine-folder file references from the app target's compile sources, add the local SwiftPM package as a dependency, and link `MercantisCore` in the app target. The library declaration itself is sufficient for Hub to start consuming Core today.
- The XCTest files in `mercantis coreTests/` use `@testable import mercantis_core` (the Xcode app module name). They are not yet wired as a SwiftPM `testTarget` against `MercantisCore`. P0.1 already tracks the Xcode-side wire-up; mirroring as a SwiftPM test target would require `@testable import MercantisCore` and is left to follow up.
- The CLI target consolidating onto `MercantisCore` (instead of its own raw-SQLite path) remains P2.3.

### P2.7 — Hub-on-Core readiness: what is sufficient vs. what is still missing [S, low risk] — ADR-007

This is a gap-analysis item, not a criticism of ADR-007. The direction in ADR-007 is correct. The question is: *how much of it is already true?*

**What is strong enough to start Hub today:**

The engine core — `DocumentEngine`, `WorkflowEngine`, `ValidationPipeline`, `PermissionEngine`, `SyncEngine`, `MetaComposer`, `AppInstaller`, and the `GenericFormView` / `GenericListView` shell — is in good working order, covered by tests, and sufficient to build Hub's back-office document foundations. Starting Hub now, against the current public API, is the right way to discover which Core capabilities are missing or incomplete. ADR-007 anticipated this: "if Hub needs functionality that Core does not yet provide, the correct approach is to extend Core's public API".

**What is not yet sufficient to claim ADR-007 is fully realised:**

The subsystems explicitly recorded as missing in `IMPLEMENTATION-STATUS.md` are not cosmetic. Several are load-bearing for any non-trivial ERP module:

| Missing subsystem | Why it matters for Hub |
|---|---|
| ~~Naming (ADR-014, P1.1)~~ ✅ shipped 2026-04-23 | Hub documents can now declare `autoname: "naming_series:SINV-.YYYY.-.####"` and get ERP-shaped IDs. Offline multi-device counter reconciliation is the remaining gap. |
| ~~Automation runtime (ADR-019/025, P1.2/P1.3)~~ ✅ shipped 2026-04-24 | Declarative `AutomationRule`s and `documentEventSubscription`s now route through `AutomationActionRegistry`. "On submit, deduct stock" is expressible as a `set_value` / `validate` pair on the manifest side. Remaining gaps: pre-commit blocking inside the save transaction, scheduler-driven rules (P1.4), and persistent notification / assignment storage. |
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
| 3 | P0.5A (rewrite permissions doc) ✅; P0.5B (implement chain) deferred; P0.8 version reader ✅; P1.5 real validation stages ✅. |
| 4 | P1.1 Naming subsystem ✅ (2026-04-23). |
| 5 | P1.3 Extension-point resolution ✅ (2026-04-24). |
| 6 | P1.2 Automation runtime ✅ (2026-04-24) (fills the `ExtensionActionDispatcher` seam). |
| 6 | P1.4 Scheduler ✅ (2026-04-24) (fills the `ExtensionSchedulerRegistrar` seam). |
| 6 | P1.6 FieldValue expansion ✅ (2026-04-24) (tagged envelope, backward-compatible decode). |
| 7 | P1.7 row-level expression permissions ✅ (2026-04-25) (`user.*` namespace, fail-closed). |
| 7 | P2.6 MercantisCore library product ✅ (2026-04-25) (Hub-importable engine target; UI stays in the app). |
| 7 | P2.5 list filters / sorting / paging ✅ (2026-04-25) (whereExpression, ListSort, limit/offset; IndexDefinition wired to SQLite expression indexes). |
| 7 | P2.1 ExpressionEvaluator AST ✅ (2026-04-25) (Parser → typed `ExpressionNode`, source positions, `referencedFields` static analysis wired into `SchemaValidator`, parse-cache, constant folding). |
| 7 | P2.2 cross-document `lookup()` ✅ (2026-04-25) (`DocumentLookupResolver` + read-through `CachingDocumentLookupResolver` with per-save invalidation; `DocumentEngine.list` `whereExpression` runs through the cached evaluator; ADR-029 lands the sandbox + budget posture). |
| 7 | P2.3 CLI / app install consolidation ✅ (2026-04-25) (`AppInstaller.install(manifestData:)` + CLI consumes `MercantisCore`; canonical schema everywhere; `FieldDefinition` decoder lenient on layout fields; expression indexes created uniformly). |

P2.6 (Core library productization) ✅ shipped 2026-04-25 — the `MercantisCore` library product now exists, so Hub development can start importing Core via `.package(url: ...)`. P2.7 (Hub readiness gap analysis) is a documentation item that can run in parallel with any P1 work. P2.4 (dashboard runtime) and P2.8 (richer field/control model) are both medium-term items best driven by Hub's concrete needs rather than by speculative pre-design.

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